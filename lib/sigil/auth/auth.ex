if Code.ensure_loaded?(Ecto) do
  defmodule Sigil.Auth do
    @moduledoc """
    Authentication context for Sigil applications.

    Provides functions for user registration, login, and retrieval.

    ## Configuration

    Set the repo in your config:

        config :sigil, :auth_repo, MyApp.Repo

    Or it defaults to `Sigil.Repo`.

    ## Usage

        {:ok, user} = Sigil.Auth.register(%{email: "me@example.com", password: "secret123"})
        {:ok, user} = Sigil.Auth.login("me@example.com", "secret123")
        user = Sigil.Auth.get_user(1)
    """

    import Ecto.Query

    @doc "Register a new user."
    def register(attrs) do
      %Sigil.Auth.User{}
      |> Sigil.Auth.User.registration_changeset(attrs)
      |> repo().insert()
    end

    @doc "Authenticate a user by email and password."
    def login(email, password) do
      user = repo().get_by(Sigil.Auth.User, email: email)

      cond do
        user && Sigil.Auth.Password.verify(password, user.password_hash) ->
          {:ok, user}

        user ->
          {:error, :invalid_password}

        true ->
          # Prevent timing attacks
          Sigil.Auth.Password.no_user_verify()
          {:error, :not_found}
      end
    end

    @doc "Get a user by ID."
    def get_user(id) do
      repo().get(Sigil.Auth.User, id)
    end

    @doc "Get a user by email."
    def get_user_by_email(email) do
      repo().get_by(Sigil.Auth.User, email: email)
    end

    @doc "List all users."
    def list_users do
      repo().all(from(u in Sigil.Auth.User, order_by: [asc: u.email]))
    end

    defp repo do
      Application.get_env(:sigil, :auth_repo, Sigil.Repo)
    end
  end
end
