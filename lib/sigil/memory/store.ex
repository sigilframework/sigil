defmodule Sigil.Memory.Store do
  @moduledoc """
  Behaviour for long-term memory persistence.

  Implementations store conversation history and other data
  in PostgreSQL for retrieval across sessions and restarts.
  """

  @type message :: %{role: String.t(), content: String.t()}

  @doc "Save messages for a session."
  @callback save(session_id :: String.t(), messages :: [message()]) ::
              :ok | {:error, term()}

  @doc "Recall messages for a session."
  @callback recall(session_id :: String.t(), opts :: keyword()) ::
              {:ok, [message()]} | {:error, term()}

  @doc "Search memory by semantic similarity."
  @callback search(session_id :: String.t(), query :: String.t(), opts :: keyword()) ::
              {:ok, [message()]} | {:error, term()}

  @optional_callbacks [search: 3]
end
