if Code.ensure_loaded?(WebSock) do
  defmodule Sigil.Live.Channel do
    @moduledoc """
    WebSocket handler for Live view connections.

    Each connected client gets its own process. This process:
    1. Receives the session ID + CSRF token from the client's first message
    2. Verifies the CSRF token before accepting the connection
    3. Rehydrates the view state from the session store (ETS)
    4. Handles events from the client (clicks, form submits)
    5. Re-renders the view on state changes
    6. Diffs the HTML and sends patches to the client

    Implements the `WebSock` behaviour for use with Bandit.
    """

    @behaviour WebSock

    require Logger

    @impl true
    def init(_state) do
      {:ok, %{view: nil, assigns: %{}, session_id: nil, last_html: nil, csrf_token: nil}}
    end

    @impl true
    def handle_in({message, [opcode: :text]}, state) do
      case Jason.decode(message) do
        {:ok, payload} ->
          handle_message(payload, state)

        {:error, _} ->
          Logger.warning("[Sigil.Live] Invalid JSON: #{inspect(message)}")
          {:ok, state}
      end
    end

    def handle_in(_other, state), do: {:ok, state}

    @impl true
    def handle_info(message, state) do
      if state.view && function_exported?(state.view, :handle_info, 2) do
        socket = %{assigns: state.assigns, id: state.session_id, connected?: true}

        case state.view.handle_info(message, socket) do
          {:noreply, new_socket} ->
            state = %{state | assigns: new_socket.assigns}
            maybe_push_diff(state)

          _ ->
            {:ok, state}
        end
      else
        {:ok, state}
      end
    end

    @impl true
    def terminate(_reason, state) do
      # Clean up session from store when WebSocket disconnects
      if state.session_id do
        Sigil.Live.SessionStore.delete(state.session_id)
      end

      :ok
    end

    # --- Message handlers ---

    # Client sends "join" with session ID and CSRF token
    defp handle_message(%{"type" => "join", "session" => session_id} = payload, state) do
      csrf_token = Map.get(payload, "csrf", "")

      # Verify CSRF token
      unless Sigil.CSRF.verify_token(csrf_token, session_id) do
        Logger.warning("[Sigil.Live] CSRF verification failed for session: #{session_id}")
        reply = Jason.encode!(%{type: "error", reason: "csrf_failed"})
        {:reply, :ok, {:text, reply}, state}
      else
        case Sigil.Live.SessionStore.get(session_id) do
          nil ->
            # Stale session — try to recover by fresh-mounting the view
            view_name = Map.get(payload, "view", "")
            path = Map.get(payload, "path", "/")

            case resolve_view_module(view_name) do
              {:ok, view} ->
                Logger.debug("[Sigil.Live] Recovering stale session #{session_id} — fresh mount of #{inspect(view)}")

                # Build minimal params from the path
                params = parse_path_params(path)
                socket = %{assigns: %{}, id: session_id, connected?: true}
                {:ok, socket} = view.mount(params, socket)

                # Store the fresh session so future reconnects work
                Sigil.Live.SessionStore.put(session_id, %{
                  view: view,
                  assigns: socket.assigns,
                  params: params
                })

                html = view.render(socket.assigns)

                state = %{
                  state
                  | view: view,
                    assigns: socket.assigns,
                    session_id: session_id,
                    last_html: html,
                    csrf_token: csrf_token
                }

                # Send joined + full HTML patch to rehydrate the client
                reply = Jason.encode!(%{type: "joined", session: session_id})
                patch = Jason.encode!(%{type: "patch", patches: [%{op: "replace_inner", html: html}]})
                {:push, [{:text, reply}, {:text, patch}], state}

              :error ->
                Logger.debug("[Sigil.Live] Stale session #{session_id}, no view to recover — reload")
                reply = Jason.encode!(%{type: "error", reason: "unknown_session", action: "reload"})
                {:reply, :ok, {:text, reply}, state}
            end

          %{view: view, assigns: assigns, params: params} ->
            # Rehydrate — remount as connected
            socket = %{assigns: assigns, id: session_id, connected?: true}
            {:ok, socket} = view.mount(params, socket)

            # Render initial HTML for diffing baseline
            html = view.render(socket.assigns)

            state = %{
              state
              | view: view,
                assigns: socket.assigns,
                session_id: session_id,
                last_html: html,
                csrf_token: csrf_token
            }

            reply = Jason.encode!(%{type: "joined", session: session_id})
            {:reply, :ok, {:text, reply}, state}
        end
      end
    end

    # Client sends an event (click, submit, etc.)
    defp handle_message(%{"type" => "event", "event" => event, "value" => value}, state) do
      if state.view == nil do
        Logger.warning("[Sigil.Live] Event before join: #{event}")
        {:ok, state}
      else
        socket = %{assigns: state.assigns, id: state.session_id, connected?: true}

        case state.view.handle_event(event, value || %{}, socket) do
          {:noreply, new_socket} ->
            state = %{state | assigns: new_socket.assigns}
            maybe_push_diff(state)

          _ ->
            {:ok, state}
        end
      end
    end

    defp handle_message(payload, state) do
      Logger.debug("[Sigil.Live] Unknown message: #{inspect(payload)}")
      {:ok, state}
    end

    # --- Diffing ---

    defp maybe_push_diff(state) do
      new_html = state.view.render(state.assigns)

      if new_html != state.last_html do
        # Send full innerHTML replacement — simple, robust, and correct
        # for complex layouts. The tiny overhead of sending full HTML is
        # negligible for most views.
        reply =
          Jason.encode!(%{
            type: "patch",
            patches: [%{op: "replace_inner", html: new_html}]
          })

        state = %{state | last_html: new_html}
        {:reply, :ok, {:text, reply}, state}
      else
        {:ok, state}
      end
    end

    # --- View resolution for stale session recovery ---

    defp resolve_view_module(view_name) when is_binary(view_name) and view_name != "" do
      # view_name comes from data-sigil-view, e.g. "Elixir.SigilDemo.ChatLive"
      # Strip "Elixir." prefix if present since Module.concat handles it
      clean_name =
        view_name
        |> String.trim()
        |> String.replace_prefix("Elixir.", "")

      try do
        module = String.to_existing_atom("Elixir." <> clean_name)

        if Code.ensure_loaded?(module) and function_exported?(module, :mount, 2) do
          {:ok, module}
        else
          :error
        end
      rescue
        ArgumentError -> :error
      end
    end

    defp resolve_view_module(_), do: :error

    defp parse_path_params(path) when is_binary(path) do
      segments =
        path
        |> String.trim_leading("/")
        |> String.split("/")
        |> Enum.reject(&(&1 == ""))

      # Build params from path segments using the router convention:
      # /resource/:slug → %{"slug" => value}
      # /resource/:id/action → %{"id" => value}
      case segments do
        [_, param] -> %{"slug" => param, "id" => param, "_path" => path}
        [_, param, _action] -> %{"id" => param, "_path" => path}
        _ -> %{"_path" => path}
      end
    end

    defp parse_path_params(_), do: %{}
  end
end
