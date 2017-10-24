defmodule Eden do
  @moduledoc """
  Adapted heavily from http://teamon.eu/2017/setting-up-elixir-cluster-using-docker-and-rancher/

  Basically, the idea is to have a generic lib. to store Elixir process info in
  etcd to use for distributed Elixir node discovery. 

  Example use:

      children = [
        # ...
        worker(Eden, ["service_name"])
      ]

  Use Distillery to set up vm.args:

      -name ${NODE_LONGNAME}
      -setcookie ${COOKIE} # get from env
      -smp auto
  """

  use GenServer

  alias Eden.Platform

  require Logger

  # Attempt to connect to new nodes every 5 seconds. 
  # TODO: Make this configurable?
  @connect_interval 5000

  def start_link(opts) do
    GenServer.start_link __MODULE__, opts, name: __MODULE__
  end

  def init(opts) do
    # Trap exits so we can respond
    Process.flag :trap_exit, true

    unless is_nil System.get_env("NODE_LONGNAME") do
      Node.start(System.get_env("NODE_LONGNAME"))
    else
      raise "No node longname provided!?"
    end

    # Expect just a name as input
    name = opts
    hash = :crypto.hash(:md5, :os.system_time(:millisecond) 
                              |> Integer.to_string) 
                              |> Base.encode16 
                              |> String.downcase
    state = %{
      name: name,
      hash: hash
    }
    send self(), :connect

    {:ok, state}
  end

  def handle_info(:connect, state) do
    dir_name = "eden_registry_" <> to_string(state[:name])

    # Note: This does re-set the key each time the :connect call is handled.
    # The justification for this is that, if the etcd cluster loses the info
    # for whatever reason, we can try and recover ourselves from it

    # Ensure the registry even exists
    registry = Violet.list_dir dir_name
    if is_nil registry do
      Logger.warn "Etcd registry doesn't exist, doing initial setup..."
      Violet.make_dir dir_name
    else
    end

    # Register ourselves
    # We don't need to care about the hostname, so we just map the hash to the
    # hostaddr
    hostname_ip = Platform.hostname_with_ip()
    Violet.set dir_name, state[:hash], hostname_ip[:hostaddr]

    # Start connecting
    unless is_nil registry do
      for node_info <- registry do
        # Logger.info "Node: #{inspect node_info}"
        node_hash = node_info["key"] |> String.split("/") |> List.last
        node_ip = node_info["value"]
        Logger.info "Connecting to #{inspect state[:name]}@#{inspect node_ip} identified by #{inspect node_hash}"
        # Don't worry about connecting to ourselves because it's handled for us
        case Node.connect :"#{state[:name]}@#{node_ip}" do
          true -> Logger.info "Connected to #{inspect state[:name]}@#{inspect node_ip}"
          # TODO: Dead node tracking
          false -> Logger.warn "Couldn't connect to #{inspect state[:name]}@#{inspect node_ip}"
          :ignored -> Logger.warn "Local node is not alive for node #{inspect state[:name]}@#{inspect node_ip}!?"
        end
      end

      Logger.info "Eden is connected to the following nodes: #{inspect Node.list}"
    end

    # Handle reconnects etc.
    Process.send_after self(), :connect, @connect_interval

    {:noreply, state}
  end

  def terminate(_reason, _state) do
    # Clean ourselves from the etcd registry
    Logger.info "Eden GenServer terminating, cleaning self from registry..."
  end
end
