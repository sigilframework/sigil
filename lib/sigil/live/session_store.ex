defmodule Sigil.Live.SessionStore do
  @moduledoc """
  ETS-backed session store for Live view state with automatic TTL cleanup.

  Replaces `:persistent_term` to prevent memory leaks. Each session
  has a configurable TTL (default: 30 minutes). Sessions are touched
  on WebSocket join to prevent expiry during active use.

  Started automatically as part of the Sigil supervision tree.
  """

  use GenServer

  @table :sigil_live_sessions
  @default_ttl_ms :timer.minutes(30)
  @cleanup_interval_ms :timer.minutes(5)

  # --- Client API ---

  @doc "Store a Live view session."
  def put(session_id, session_data) do
    ttl = Application.get_env(:sigil, :live_session_ttl_ms, @default_ttl_ms)
    expires_at = System.monotonic_time(:millisecond) + ttl
    :ets.insert(@table, {session_id, session_data, expires_at})
    :ok
  end

  @doc "Retrieve a session, returning nil if expired or missing."
  def get(session_id) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, data, expires_at}] ->
        now = System.monotonic_time(:millisecond)

        if now < expires_at do
          # Touch: extend TTL on access
          ttl = Application.get_env(:sigil, :live_session_ttl_ms, @default_ttl_ms)
          new_expires = now + ttl
          :ets.update_element(@table, session_id, {3, new_expires})
          data
        else
          :ets.delete(@table, session_id)
          nil
        end

      [] ->
        nil
    end
  end

  @doc "Delete a session."
  def delete(session_id) do
    :ets.delete(@table, session_id)
    :ok
  end

  @doc "Count active sessions (for monitoring)."
  def count do
    :ets.info(@table, :size)
  end

  # --- GenServer (cleanup timer) ---

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    table = :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    schedule_cleanup()
    {:ok, %{table: table}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = System.monotonic_time(:millisecond)

    # Delete all expired sessions
    # Match spec: select entries where expires_at < now
    :ets.select_delete(@table, [
      {{:"$1", :_, :"$3"}, [{:<, :"$3", now}], [true]}
    ])

    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    interval = Application.get_env(:sigil, :live_session_cleanup_ms, @cleanup_interval_ms)
    Process.send_after(self(), :cleanup, interval)
  end
end
