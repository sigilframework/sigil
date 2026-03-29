if Code.ensure_loaded?(Plug) do
  defmodule Sigil.Live.Handler do
    @moduledoc """
    Handles the HTTP side of Live views.

    On initial page load (HTTP GET), this module:
    1. Creates a socket
    2. Calls the view's `mount/2`
    3. Calls the view's `render/1`
    4. Wraps the result in a layout with CSRF meta tag
    5. Sends the HTML response
    6. Stores session in ETS with TTL (not persistent_term)

    The rendered page includes sigil.js which opens a WebSocket
    connection for subsequent real-time updates.

    ## Session Data

    The Plug session (cookie-based) is passed to `mount/2` via
    `params["_session"]`. Views can write back to the session by
    setting `socket.assigns.__session__` to a map of key/value pairs.
    """

    import Plug.Conn

    @doc """
    Handle an HTTP request for a Live view.

    Mounts the view, renders it, wraps it in a layout, and sends
    the response as HTML.
    """
    def handle_http(conn, view_module, opts \\ []) do
      # Create initial socket with request params
      # Include session data so views can read cookies/session state
      session_data = get_session_data(conn)
      params = Map.merge(conn.params || %{}, path_params(conn))
      params = Map.put(params, "_session", session_data)
      params = Map.put(params, "_path", conn.request_path)

      socket = Sigil.Live.new_socket()
      socket = Map.put(socket, :connected?, false)

      # Pass auth state from conn into socket assigns
      socket =
        if conn.assigns[:current_user] do
          Sigil.Live.assign(socket, current_user: conn.assigns.current_user)
        else
          socket
        end

      # Mount the view
      {:ok, socket} = view_module.mount(params, socket)

      # Write session values back from socket assigns
      conn = apply_session_writes(conn, socket.assigns)

      # Render the view
      inner_html = view_module.render(socket.assigns)

      # Generate a unique session ID for this view instance
      session_id = Sigil.Live.generate_id()

      # Store the view state in ETS (with TTL) instead of persistent_term
      Sigil.Live.SessionStore.put(session_id, %{
        view: view_module,
        assigns: socket.assigns,
        params: params
      })

      # Generate CSRF token for this session
      csrf_token = Sigil.CSRF.generate_token(session_id)

      # Wrap rendered content with Live container div
      live_html = """
      <div id="sigil-live-#{session_id}"
           class="h-full flex flex-col"
           data-sigil-session="#{session_id}"
           data-sigil-csrf="#{csrf_token}"
           data-sigil-view="#{inspect(view_module)}">
        #{inner_html}
      </div>
      """

      # Wrap in layout
      layout = Keyword.get(opts, :layout)

      assigns =
        socket.assigns
        |> Map.put(:__view__, inspect(view_module))
        |> Map.put(:__csrf_token__, csrf_token)
        |> Map.put(:__session_id__, session_id)

      full_html =
        if layout do
          {layout_mod, layout_fn} = layout
          Sigil.Layout.render(layout_mod, layout_fn, assigns, live_html)
        else
          Sigil.Layout.default_layout(assigns, live_html)
        end

      conn
      |> put_resp_content_type("text/html")
      |> send_resp(200, full_html)
    end

    # Read all session values into a map for the view
    defp get_session_data(conn) do
      try do
        # Plug.Conn.get_session/1 returns the full session map
        Plug.Conn.get_session(conn)
      rescue
        _ -> %{}
      end
    end

    # If the view set __session__ in assigns, write those values to the Plug session
    defp apply_session_writes(conn, assigns) do
      case Map.get(assigns, :__session__, nil) do
        nil ->
          conn

        session_writes when is_map(session_writes) ->
          Enum.reduce(session_writes, conn, fn {key, value}, conn ->
            Plug.Conn.put_session(conn, key, value)
          end)

        _ ->
          conn
      end
    end

    defp path_params(conn) do
      conn.path_params || %{}
    rescue
      _ -> %{}
    end
  end
end
