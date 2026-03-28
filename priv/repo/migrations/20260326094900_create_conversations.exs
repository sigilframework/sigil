defmodule Relay.Repo.Migrations.CreateConversations do
  use Ecto.Migration

  def change do
    create table(:conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :session_id, :string, null: false
      add :role, :string, null: false
      add :content, :text, null: false
      add :metadata, :map, default: %{}
      add :sequence, :integer, null: false
      add :token_count, :integer, default: 0

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:conversations, [:session_id, :sequence])
    create index(:conversations, [:session_id])
  end
end
