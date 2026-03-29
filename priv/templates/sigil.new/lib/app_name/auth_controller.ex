defmodule MyApp.AuthController do
  import Plug.Conn

  def login(conn, _opts) do
    email = conn.body_params["email"]
    password = conn.body_params["password"]

    case Sigil.Auth.login(email, password) do
      {:ok, user} ->
        conn
        |> put_session(:user_id, user.id)
        |> put_resp_header("location", "/admin")
        |> send_resp(302, "")
        |> halt()

      {:error, _reason} ->
        conn
        |> put_resp_header("location", "/login?error=invalid")
        |> send_resp(302, "")
        |> halt()
    end
  end

  def logout(conn, _opts) do
    conn
    |> configure_session(drop: true)
    |> put_resp_header("location", "/")
    |> send_resp(302, "")
    |> halt()
  end
end
