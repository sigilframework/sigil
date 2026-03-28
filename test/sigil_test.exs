defmodule SigilTest do
  use ExUnit.Case, async: true

  test "version returns current version" do
    assert Sigil.version() == "0.1.0"
  end
end
