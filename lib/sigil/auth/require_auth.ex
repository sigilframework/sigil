if Code.ensure_loaded?(Plug) do
defmodule Sigil.Auth.RequireAuth do
  @moduledoc """
  Plug that requires authentication.

  Redirects to the login page if no user is logged in.

      # In your router
      plug Sigil.Auth.RequireAuth
  """
  @behaviour Plug
  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      login_path = Application.get_env(:sigil, :login_path, "/login")

      conn
      |> put_resp_header("location", login_path)
      |> send_resp(302, "")
      |> halt()
    end
  end
end
end
