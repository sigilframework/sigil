defmodule Sigil.Live do
  @moduledoc """
  Behaviour for real-time web views over WebSocket.

  Sigil.Live provides server-rendered, real-time web pages
  with minimal client-side JavaScript (~2KB).

  ## Defining a Live View

      defmodule MyApp.DashboardLive do
        use Sigil.Live

        @impl true
        def mount(params, socket) do
          {:ok, assign(socket, count: 0)}
        end

        @impl true
        def render(assigns) do
          ~s(<div>Count: \#{assigns.count}</div>)
        end

        @impl true
        def handle_event("increment", _params, socket) do
          {:noreply, assign(socket, count: socket.assigns.count + 1)}
        end
      end

  > **Note:** Full Live implementation (WebSocket transport, DOM diffing,
  > client JS) will be built in a later phase. This module defines the
  > target behaviour and basic socket structure.
  """

  @type socket :: %{
          assigns: map(),
          id: String.t(),
          connected?: boolean()
        }

  @doc "Called when the view is mounted. Initialize assigns here."
  @callback mount(params :: map(), socket :: socket()) ::
              {:ok, socket()}

  @doc "Render HTML from the current assigns."
  @callback render(assigns :: map()) :: String.t()

  @doc "Handle a client event (button click, form submit, etc.)."
  @callback handle_event(event :: String.t(), params :: map(), socket :: socket()) ::
              {:noreply, socket()}

  @doc "Handle a server-side message (e.g., from an agent process)."
  @callback handle_info(message :: term(), socket :: socket()) ::
              {:noreply, socket()}

  @optional_callbacks [handle_info: 2]

  defmacro __using__(_opts) do
    quote do
      @behaviour Sigil.Live

      @impl Sigil.Live
      def handle_info(_message, socket), do: {:noreply, socket}

      defoverridable handle_info: 2

      @doc false
      def __live__?, do: true
    end
  end

  @doc "Create a new socket with default assigns."
  def new_socket(id \\ nil) do
    %{
      assigns: %{},
      id: id || generate_id(),
      connected?: false
    }
  end

  @doc "Assign a value to the socket."
  def assign(socket, key, value) when is_atom(key) do
    put_in(socket, [:assigns, key], value)
  end

  @doc "Assign multiple values to the socket."
  def assign(socket, keyword) when is_list(keyword) do
    Enum.reduce(keyword, socket, fn {key, value}, acc ->
      assign(acc, key, value)
    end)
  end

  @doc "Generate a unique ID for a Live session."
  def generate_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
