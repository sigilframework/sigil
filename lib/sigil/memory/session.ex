defmodule Sigil.Memory.Session do
  @moduledoc """
  ETS-based session memory for short-term data.

  Stores per-session key-value pairs that persist across multiple
  agent interactions within a session but are lost on restart.

  Used for preferences, summaries, and working state that
  doesn't need to be persisted to the database.
  """
  use GenServer

  @table :sigil_sessions

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Get a value from the session store."
  def get(session_id, key, default \\ nil) do
    case :ets.lookup(@table, {session_id, key}) do
      [{_, value}] -> value
      [] -> default
    end
  end

  @doc "Put a value into the session store."
  def put(session_id, key, value) do
    :ets.insert(@table, {{session_id, key}, value})
    :ok
  end

  @doc "Delete a key from the session store."
  def delete(session_id, key) do
    :ets.delete(@table, {session_id, key})
    :ok
  end

  @doc "Get all key-value pairs for a session."
  def get_all(session_id) do
    pattern = {{session_id, :"$1"}, :"$2"}
    :ets.match(@table, pattern)
    |> Enum.map(fn [key, value] -> {key, value} end)
    |> Map.new()
  end

  @doc "Clear all data for a session."
  def clear(session_id) do
    pattern = {{session_id, :_}, :_}
    :ets.match_delete(@table, pattern)
    :ok
  end

  # GenServer callbacks

  @impl true
  def init(_) do
    table = :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, table}
  end
end
