defmodule Journal.ConversationPubSub do
  @moduledoc """
  Lightweight real-time sync for conversations using OTP's :pg.

  Both the visitor's ChatLive and the admin's ConversationDetailLive
  join the same :pg group. When either side adds a message, it broadcasts
  to all group members.
  """

  @scope :journal_conversations

  @doc "Subscribe the calling process to conversation updates."
  def subscribe(conversation_id) do
    :pg.join(@scope, topic(conversation_id), self())
  end

  @doc "Unsubscribe the calling process."
  def unsubscribe(conversation_id) do
    :pg.leave(@scope, topic(conversation_id), self())
  end

  @doc "Broadcast a message to all subscribers of a conversation."
  def broadcast(conversation_id, message) do
    for pid <- :pg.get_members(@scope, topic(conversation_id)),
        pid != self() do
      send(pid, message)
    end

    :ok
  end

  defp topic(conversation_id), do: "conversation:#{conversation_id}"
end
