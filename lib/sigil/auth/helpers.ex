if Code.ensure_loaded?(Plug) do
defmodule Sigil.Auth.Helpers do
  @moduledoc """
  Helper functions for auth operations in Live views and plugs.

  ## Usage in a Live view

      def handle_event("login", %{"email" => email, "password" => password}, socket) do
        case Sigil.Auth.login(email, password) do
          {:ok, user} ->
            # Session is set via the login redirect
            {:noreply, assign(socket, :login_result, {:ok, user})}

          {:error, _} ->
            {:noreply, assign(socket, :error, "Invalid email or password")}
        end
      end
  """
  import Plug.Conn

  @doc "Log a user in by setting the session."
  def log_in(conn, user) do
    conn
    |> put_session(:user_id, user.id)
    |> configure_session(renew: true)
  end

  @doc "Log a user out by clearing the session."
  def log_out(conn) do
    conn
    |> delete_session(:user_id)
    |> configure_session(drop: true)
  end
end
end
