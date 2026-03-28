if Code.ensure_loaded?(Ecto) do
  defmodule Sigil.Auth.User do
    @moduledoc """
    User schema for authentication.

    Stores email and bcrypt-hashed password. Can be extended
    by the application with additional fields.

    ## Migration

    Create the users table:

        mix ecto.gen.migration create_users

    Then add:

        def change do
          create table(:users) do
            add :email, :citext, null: false
            add :password_hash, :string, null: false
            timestamps()
          end

          create unique_index(:users, [:email])
        end
    """
    use Ecto.Schema
    import Ecto.Changeset

    schema "users" do
      field(:email, :string)
      field(:password_hash, :string)
      field(:password, :string, virtual: true)
      timestamps()
    end

    @doc "Changeset for registration — validates email/password, hashes password."
    def registration_changeset(user, attrs) do
      user
      |> cast(attrs, [:email, :password])
      |> validate_required([:email, :password])
      |> validate_format(:email, ~r/@/, message: "must be a valid email")
      |> validate_length(:password, min: 8, message: "must be at least 8 characters")
      |> unique_constraint(:email)
      |> hash_password()
    end

    @doc "Changeset for login — validates presence only."
    def login_changeset(user, attrs) do
      user
      |> cast(attrs, [:email, :password])
      |> validate_required([:email, :password])
    end

    defp hash_password(changeset) do
      case get_change(changeset, :password) do
        nil ->
          changeset

        password ->
          changeset
          |> put_change(:password_hash, Sigil.Auth.Password.hash(password))
          |> delete_change(:password)
      end
    end
  end
end
