defmodule MyApp.Message do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "messages" do
    field :role, :string
    field :content, :string

    belongs_to :conversation, MyApp.Conversation, type: :binary_id

    # Only inserted_at — messages are immutable
    timestamps(updated_at: false)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:conversation_id, :role, :content])
    |> validate_required([:conversation_id, :role, :content])
    |> validate_inclusion(:role, ["user", "ai", "admin"])
  end
end
