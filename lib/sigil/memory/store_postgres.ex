if Code.ensure_loaded?(Ecto) do
defmodule Sigil.Memory.Store.Postgres do
  @moduledoc """
  PostgreSQL implementation of `Sigil.Memory.Store`.

  Stores conversation messages in a `conversations` table for
  retrieval across sessions and restarts. This is Tier 3 (long-term)
  memory — the persistent layer that survives process crashes,
  node restarts, and deployments.

  ## Setup

  Requires the `conversations` table (see migration below) and
  optionally pgvector for semantic search.

  ## Usage

      # Save messages
      Sigil.Memory.Store.Postgres.save("session_123", messages)

      # Recall recent messages
      {:ok, messages} = Sigil.Memory.Store.Postgres.recall("session_123", limit: 50)

      # Semantic search (requires pgvector + embeddings)
      {:ok, results} = Sigil.Memory.Store.Postgres.search("session_123", "invoice total")
  """

  @behaviour Sigil.Memory.Store

  import Ecto.Query

  defmodule Message do
    use Ecto.Schema

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "conversations" do
      field :session_id, :string
      field :role, :string
      field :content, :string
      field :metadata, :map, default: %{}
      field :sequence, :integer
      field :token_count, :integer, default: 0

      timestamps(type: :utc_datetime, updated_at: false)
    end
  end

  @impl true
  def save(session_id, messages) when is_list(messages) do
    # Get the next sequence number
    base_seq = next_sequence(session_id)

    entries =
      messages
      |> Enum.with_index()
      |> Enum.map(fn {msg, idx} ->
        content = extract_content(msg.content)
        token_count = Sigil.Memory.Tokenizer.count(content)

        %{
          id: Ecto.UUID.generate(),
          session_id: session_id,
          role: to_string(msg[:role] || msg["role"]),
          content: content,
          metadata: Map.drop(msg, [:role, :content, "role", "content"]) |> safe_metadata(),
          sequence: base_seq + idx,
          token_count: token_count,
          inserted_at: DateTime.utc_now()
        }
      end)

    case repo().insert_all(Message, entries) do
      {count, _} when count > 0 -> :ok
      _ -> {:error, :insert_failed}
    end
  end

  @impl true
  def recall(session_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    from_seq = Keyword.get(opts, :from_sequence, 0)

    query =
      from m in Message,
        where: m.session_id == ^session_id and m.sequence >= ^from_seq,
        order_by: [asc: m.sequence],
        limit: ^limit

    messages =
      repo().all(query)
      |> Enum.map(fn row ->
        %{role: row.role, content: row.content}
      end)

    {:ok, messages}
  end

  @impl true
  def search(session_id, query, opts \\ []) do
    # Basic text search fallback (pgvector search would go here)
    limit = Keyword.get(opts, :limit, 10)

    sql_query =
      from m in Message,
        where: m.session_id == ^session_id,
        where: ilike(m.content, ^"%#{query}%"),
        order_by: [desc: m.sequence],
        limit: ^limit

    messages =
      repo().all(sql_query)
      |> Enum.map(fn row ->
        %{role: row.role, content: row.content, sequence: row.sequence}
      end)

    {:ok, messages}
  end

  @doc "Count messages for a session."
  def count(session_id) do
    query = from m in Message, where: m.session_id == ^session_id, select: count(m.id)
    repo().one(query) || 0
  end

  @doc "Delete all messages for a session."
  def clear(session_id) do
    query = from m in Message, where: m.session_id == ^session_id
    repo().delete_all(query)
    :ok
  end

  # Private

  defp next_sequence(session_id) do
    query = from m in Message, where: m.session_id == ^session_id, select: max(m.sequence)
    (repo().one(query) || 0) + 1
  end

  defp extract_content(content) when is_binary(content), do: content

  defp extract_content(blocks) when is_list(blocks) do
    Enum.map_join(blocks, "
", fn
      %{text: text} -> text
      %{"text" => text} -> text
      %{content: content} -> to_string(content)
      %{"content" => content} -> to_string(content)
      other -> inspect(other)
    end)
  end

  defp extract_content(other), do: to_string(other)

  defp safe_metadata(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), safe_value(v)} end)
  end

  defp safe_value(v) when is_atom(v), do: to_string(v)
  defp safe_value(v) when is_pid(v), do: inspect(v)
  defp safe_value(v) when is_function(v), do: inspect(v)
  defp safe_value(v), do: v

  defp repo do
    Application.get_env(:sigil, :repo, Sigil.Repo)
  end
end
end
