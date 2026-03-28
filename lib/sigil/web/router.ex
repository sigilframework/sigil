if Code.ensure_loaded?(Plug) do
defmodule Sigil.Router do
  @moduledoc """
  Routing DSL for Sigil applications.

  ## Usage

      defmodule MyApp.Router do
        use Sigil.Router

        # Public routes
        live "/", MyApp.HomeLive
        live "/login", MyApp.LoginLive
        live "/register", MyApp.RegisterLive

        # Auth actions (POST)
        post "/auth/login", MyApp.AuthController, :login
        post "/auth/register", MyApp.AuthController, :register
        post "/auth/logout", MyApp.AuthController, :logout

        # Protected routes — require login
        live "/dashboard", MyApp.DashboardLive, auth: true

        sigil_routes()
      end
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      use Plug.Router

      import Sigil.Router, only: [live: 2, live: 3, sigil_routes: 0]

      plug Plug.Parsers, parsers: [:urlencoded, :json], pass: ["*/*"], json_decoder: Jason
      plug :match
      plug :dispatch
    end
  end

  @doc """
  Mount a Live view at a path.

  ## Options

  - `:auth` — If `true`, requires authenticated user (redirects to /login)
  - `:layout` — `{LayoutModule, :function_name}` to wrap the view
  """
  defmacro live(path, view_module, opts \\ []) do
    if Keyword.get(opts, :auth, false) do
      quote do
        get unquote(path) do
          conn = Sigil.Auth.SessionPlug.call(var!(conn), [])

          if conn.assigns[:current_user] do
            Sigil.Live.Handler.handle_http(conn, unquote(view_module), unquote(opts))
          else
            conn
            |> Plug.Conn.put_resp_header("location", "/login")
            |> Plug.Conn.send_resp(302, "")
            |> Plug.Conn.halt()
          end
        end
      end
    else
      quote do
        get unquote(path) do
          Sigil.Live.Handler.handle_http(var!(conn), unquote(view_module), unquote(opts))
        end
      end
    end
  end

  @doc """
  Call this at the end of your router to add the WebSocket endpoint,
  static asset serving, and catch-all 404.

  Must be the last thing in your router module.
  """
  defmacro sigil_routes do
    quote do
      # WebSocket upgrade endpoint for Live connections
      get "/__sigil/websocket" do
        var!(conn)
        |> WebSockAdapter.upgrade(Sigil.Live.Channel, %{}, timeout: 60_000)
        |> halt()
      end

      # Catch-all: static assets or 404
      match _ do
        case var!(conn).path_info do
          ["assets" | file_parts] ->
            Sigil.Web.Static.serve(var!(conn), file_parts)

          _ ->
            send_resp(var!(conn), 404, "Not Found")
        end
      end
    end
  end
end
end
