defmodule Sigil.Agent.Message do
  @moduledoc """
  Structured messages for inter-agent communication.

  Messages carry context metadata so receiving agents understand
  the provenance and intent of information being shared.

  ## Usage

      msg = Message.new(:researcher, :analyst, "Found Q4 revenue: $4.2M",
        context: %{source: "quarterly_report.pdf"},
        run_id: "abc-123"
      )
  """

  @type t :: %__MODULE__{
          id: String.t(),
          from: atom() | pid(),
          to: atom(),
          content: term(),
          context: map(),
          run_id: String.t() | nil,
          reply_to: String.t() | nil,
          inserted_at: DateTime.t()
        }

  defstruct [
    :id,
    :from,
    :to,
    :content,
    :run_id,
    :reply_to,
    context: %{},
    inserted_at: nil
  ]

  @doc """
  Create a new inter-agent message.

  ## Options

  - `:context` — Relevant context from the sender (default: %{})
  - `:run_id` — Originating run_id for traceability
  - `:reply_to` — Message ID this is responding to
  """
  def new(from, to, content, opts \\ []) do
    %__MODULE__{
      id: Ecto.UUID.generate(),
      from: from,
      to: to,
      content: content,
      context: Keyword.get(opts, :context, %{}),
      run_id: Keyword.get(opts, :run_id),
      reply_to: Keyword.get(opts, :reply_to),
      inserted_at: DateTime.utc_now()
    }
  end

  @doc "Create a reply to an existing message."
  def reply(%__MODULE__{} = original, content, opts \\ []) do
    new(
      original.to,
      original.from,
      content,
      Keyword.merge(opts,
        reply_to: original.id,
        run_id: original.run_id
      )
    )
  end
end
