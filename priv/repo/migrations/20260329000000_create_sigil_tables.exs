defmodule Sigil.Repo.Migrations.CreateSigilTables do
  use Ecto.Migration

  def change do
    # --- Auth ---

    execute "CREATE EXTENSION IF NOT EXISTS citext", "DROP EXTENSION IF EXISTS citext"

    create table(:users) do
      add :email, :citext, null: false
      add :password_hash, :string, null: false
      timestamps()
    end

    create unique_index(:users, [:email])

    # --- Agent Event Sourcing ---

    # Append-only event log — every meaningful thing an agent does
    create table(:agent_events, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :run_id, :binary_id, null: false
      add :agent_module, :text, null: false
      add :event_type, :text, null: false
      add :sequence, :integer, null: false
      add :payload, :map, null: false, default: %{}
      add :token_count, :integer, default: 0

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:agent_events, [:run_id, :sequence])
    create index(:agent_events, [:run_id, :event_type])
    create unique_index(:agent_events, [:run_id, :sequence])

    # Periodic snapshots of full agent state for fast resume
    create table(:agent_checkpoints, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :run_id, :binary_id, null: false
      add :sequence, :integer, null: false
      add :state, :map, null: false
      add :messages, :map, null: false
      add :config, :map, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:agent_checkpoints, [:run_id, :sequence])

    # Context snapshots — what the LLM actually saw at each call
    create table(:context_snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :run_id, :binary_id, null: false
      add :event_id, references(:agent_events, type: :bigserial)
      add :messages, :map, null: false
      add :token_count, :integer, null: false
      add :model, :text, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:context_snapshots, [:run_id])

    # --- Conversations (memory persistence) ---

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
