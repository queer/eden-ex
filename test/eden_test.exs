defmodule EdenTest do
  use ExUnit.Case
  doctest Eden

  test "greets the world" do
    assert Eden.hello() == :world
  end
end
