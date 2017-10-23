defmodule Eden.Platform do
  @moduledoc """
  Platform-specific code. Basically, this code is used to check if we're 
  running inside a docker container or not. There's no guarantees on how 
  accurate it will be, but it *should* be good enough.

  If we are running inside a docker container, we should be able to indicate as
  much to other parts of the application, so that we can 
  """

  def is_docker? do
    cond do
      hostname_with_ip()[:hostaddr] == "127.0.0.1" -> false
      true -> true
    end
  end

  def hostname_with_ip do
    {:ok, hostname} = :inet.gethostname()
    {:ok, hostaddr} = :inet.getaddr(hostname, :inet)
    %{
      hostname: to_string(hostname), 
      hostaddr: (hostaddr |> Tuple.to_list |> Enum.join("."))
    }
  end
end