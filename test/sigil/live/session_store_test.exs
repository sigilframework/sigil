defmodule Sigil.Live.SessionStoreTest do
  use ExUnit.Case, async: true

  alias Sigil.Live.SessionStore

  # The store is started by the application, but we need ETS for tests.
  # Use a try/catch in case it's already started.
  setup do
    try do
      SessionStore.start_link([])
    rescue
      _ -> :ok
    catch
      :exit, _ -> :ok
    end

    :ok
  end

  test "put and get session" do
    SessionStore.put("test-session-1", %{view: MyView, assigns: %{count: 0}})
    data = SessionStore.get("test-session-1")
    assert data.view == MyView
    assert data.assigns == %{count: 0}
  end

  test "get returns nil for unknown session" do
    assert SessionStore.get("nonexistent") == nil
  end

  test "delete removes session" do
    SessionStore.put("test-session-2", %{view: MyView})
    assert SessionStore.get("test-session-2") != nil

    SessionStore.delete("test-session-2")
    assert SessionStore.get("test-session-2") == nil
  end

  test "expired sessions return nil" do
    # Store with already-expired timestamp by directly inserting into ETS
    expired_at = System.monotonic_time(:millisecond) - 1000
    :ets.insert(:sigil_live_sessions, {"expired-session", %{view: MyView}, expired_at})

    assert SessionStore.get("expired-session") == nil
  end

  test "count returns number of sessions" do
    initial = SessionStore.count()
    SessionStore.put("count-test-1", %{view: MyView})
    SessionStore.put("count-test-2", %{view: MyView})
    assert SessionStore.count() >= initial + 2
  end
end
