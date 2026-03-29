defmodule MyApp.Conversations do
  @moduledoc """
  Context for managing chat conversations and messages.

  Each conversation stores its full message history in the `messages` table.
  When the chat agent needs context, we load all messages for the conversation
  and pass them as the conversation history.
  """

  import Ecto.Query
  alias MyApp.{Repo, Conversation, Message}

  # --- Conversations ---

  @doc "Start a new conversation, optionally linked to an agent."
  def create_conversation(attrs \\ %{}) do
    %Conversation{}
    |> Conversation.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Get a conversation by ID with messages and agent_config preloaded."
  def get_conversation!(id) do
    Conversation
    |> Repo.get!(id)
    |> Repo.preload([:messages, :agent_config])
  end

  @doc "List recent conversations, most recent first."
  def list_conversations(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Conversation
    |> order_by([c], desc: c.updated_at)
    |> limit(^limit)
    |> preload([:agent_config, :messages])
    |> Repo.all()
  end

  @doc "Count active conversations."
  def count_active do
    Conversation
    |> where([c], c.status == "active")
    |> Repo.aggregate(:count)
  end

  @doc "Close a conversation."
  def close_conversation(%Conversation{} = conv) do
    conv
    |> Conversation.changeset(%{status: "closed"})
    |> Repo.update()
  end

  @doc "Check if the last message is from the user (unanswered)."
  def has_unanswered_message?(conversation_id) do
    last_message =
      Message
      |> where([m], m.conversation_id == ^conversation_id)
      |> order_by([m], desc: m.inserted_at)
      |> limit(1)
      |> Repo.one()

    last_message && last_message.role == "user"
  end

  @doc "Get the last user message (for auto-response when switching back to agent mode)."
  def last_user_message(conversation_id) do
    Message
    |> where([m], m.conversation_id == ^conversation_id and m.role == "user")
    |> order_by([m], desc: m.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  # --- Messages ---

  @doc "Add a message to a conversation."
  def add_message(conversation_id, role, content) do
    %Message{}
    |> Message.changeset(%{conversation_id: conversation_id, role: role, content: content})
    |> Repo.insert()
  end

  @doc "Get all messages for a conversation in chronological order."
  def get_messages(conversation_id) do
    Message
    |> where([m], m.conversation_id == ^conversation_id)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  @doc """
  Get the conversation history formatted for the AI agent.
  Returns a list of %{role: "user"|"assistant", content: "..."} maps.
  """
  def get_agent_history(conversation_id) do
    conversation_id
    |> get_messages()
    |> Enum.map(fn msg ->
      api_role = if msg.role in ["ai", "admin"], do: "assistant", else: msg.role
      %{role: api_role, content: msg.content}
    end)
  end

  @doc "Auto-generate a title from the first user message."
  def maybe_set_title(%Conversation{title: nil} = conv, first_message) do
    title = first_message |> String.slice(0, 80) |> String.trim()
    title = if String.length(first_message) > 80, do: title <> "…", else: title

    conv
    |> Conversation.changeset(%{title: title})
    |> Repo.update()
  end

  def maybe_set_title(conv, _), do: {:ok, conv}

  # --- Expiry ---

  @stale_days 7

  @doc "Close conversations that have been inactive for #{@stale_days} days."
  def close_stale_conversations do
    cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -@stale_days * 86_400, :second)

    Conversation
    |> where([c], c.status == "active" and c.updated_at < ^cutoff)
    |> Repo.update_all(set: [status: "closed", updated_at: NaiveDateTime.utc_now()])
  end
end
