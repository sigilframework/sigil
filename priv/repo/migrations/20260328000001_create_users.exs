defmodule Relay.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    # Enable citext extension for case-insensitive emails
    execute "CREATE EXTENSION IF NOT EXISTS citext", "DROP EXTENSION IF EXISTS citext"

    create table(:users) do
      add :email, :citext, null: false
      add :password_hash, :string, null: false
      timestamps()
    end

    create unique_index(:users, [:email])
  end
end
