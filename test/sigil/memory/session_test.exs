defmodule Sigil.Memory.SessionTest do
  use ExUnit.Case, async: true

  alias Sigil.Memory.Session

  setup do
    session_id = "test_session_#{:erlang.unique_integer([:positive])}"
    {:ok, session_id: session_id}
  end

  test "put and get a value", %{session_id: sid} do
    Session.put(sid, :name, "Alice")
    assert Session.get(sid, :name) == "Alice"
  end

  test "get returns default when key missing", %{session_id: sid} do
    assert Session.get(sid, :missing) == nil
    assert Session.get(sid, :missing, "default") == "default"
  end

  test "delete removes a key", %{session_id: sid} do
    Session.put(sid, :key, "value")
    Session.delete(sid, :key)
    assert Session.get(sid, :key) == nil
  end

  test "get_all returns all session data", %{session_id: sid} do
    Session.put(sid, :a, 1)
    Session.put(sid, :b, 2)
    all = Session.get_all(sid)
    assert all[:a] == 1
    assert all[:b] == 2
  end

  test "clear removes all session data", %{session_id: sid} do
    Session.put(sid, :x, "one")
    Session.put(sid, :y, "two")
    Session.clear(sid)
    assert Session.get_all(sid) == %{}
  end
end
