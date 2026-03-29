defmodule MyApp.Repo.Migrations.InitSchema do
  use Ecto.Migration

  def change do
    # --- Auth ---

    create table(:users) do
      add :email, :string, null: false
      add :password_hash, :string, null: false
      timestamps()
    end

    create unique_index(:users, [:email])

    # --- Blog ---

    create table(:posts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :body, :text, default: ""
      add :tags, {:array, :string}, default: []
      add :published, :boolean, default: false
      add :published_at, :utc_datetime
      timestamps()
    end

    # --- Agent Configs ---

    create table(:agent_configs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :system_prompt, :text, null: false
      add :model, :string, default: "claude-sonnet-4-20250514"
      add :active, :boolean, default: true
      add :tools, {:array, :string}, default: []
      timestamps()
    end

    create unique_index(:agent_configs, [:slug])

    # --- Conversations ---

    create table(:conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :status, :string, default: "active"
      add :title, :string
      add :agent_config_id, references(:agent_configs, type: :binary_id, on_delete: :nilify_all)
      timestamps()
    end

    create index(:conversations, [:status])
    create index(:conversations, [:agent_config_id])

    # --- Messages ---

    create table(:messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :role, :string, null: false
      add :content, :text, null: false
      add :conversation_id, references(:conversations, type: :binary_id, on_delete: :delete_all), null: false
      timestamps(updated_at: false)
    end

    create index(:messages, [:conversation_id])

    # --- Site Settings ---

    create table(:site_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :key, :string, null: false
      add :value, :text
      timestamps()
    end

    create unique_index(:site_settings, [:key])

    # --- Agent Events (event sourcing) ---

    create table(:agent_events, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :run_id, :binary_id, null: false
      add :sequence, :integer, null: false
      add :event_type, :string, null: false
      add :payload, :map, default: %{}
      add :agent_module, :string
      timestamps(updated_at: false)
    end

    create index(:agent_events, [:run_id, :sequence])

    # --- Agent Checkpoints (crash recovery) ---

    create table(:agent_checkpoints, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :run_id, :binary_id, null: false
      add :sequence, :integer, null: false
      add :state, :map, default: %{}
      add :messages, :map, default: %{}
      add :config, :map, default: %{}
      timestamps(updated_at: false)
    end

    create index(:agent_checkpoints, [:run_id, :sequence])
  end
end
