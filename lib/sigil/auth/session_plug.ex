if Code.ensure_loaded?(Plug) do
  defmodule Sigil.Auth.SessionPlug do
    @moduledoc """
    Plug that initializes cookie-based sessions for authentication.

    Add this to your router pipeline:

        plug Sigil.Auth.SessionPlug

    This sets up encrypted cookie sessions and loads the current
    user from the session into `conn.assigns.current_user`.
    """
    @behaviour Plug

    @session_options [
      store: :cookie,
      key: "_sigil_session",
      signing_salt: "sigil_sign",
      encryption_salt: "sigil_enc",
      same_site: "Lax",
      max_age: 86_400 * 30
    ]

    @impl true
    def init(opts) do
      # Pre-compute session init at compile time for performance
      Plug.Session.init(@session_options ++ opts)
    end

    @impl true
    def call(conn, session_opts) do
      secret = Application.get_env(:sigil, :secret_key_base) || ensure_secret()

      conn
      |> Plug.Conn.put_private(:plug_skip_csrf_protection, true)
      |> Map.put(:secret_key_base, secret)
      |> Plug.Session.call(session_opts)
      |> Plug.Conn.fetch_session()
      |> load_current_user()
    end

    defp load_current_user(conn) do
      user_id = Plug.Conn.get_session(conn, :user_id)

      if user_id do
        if Code.ensure_loaded?(Sigil.Auth) do
          case Sigil.Auth.get_user(user_id) do
            nil ->
              conn
              |> Plug.Conn.delete_session(:user_id)
              |> Plug.Conn.assign(:current_user, nil)

            user ->
              Plug.Conn.assign(conn, :current_user, user)
          end
        else
          Plug.Conn.assign(conn, :current_user, nil)
        end
      else
        Plug.Conn.assign(conn, :current_user, nil)
      end
    end

    defp ensure_secret do
      secret = :crypto.strong_rand_bytes(64) |> Base.encode64(padding: false)
      Application.put_env(:sigil, :secret_key_base, secret)
      secret
    end
  end
end
