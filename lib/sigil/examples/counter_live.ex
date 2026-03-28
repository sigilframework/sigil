defmodule Sigil.Examples.CounterLive do
  @moduledoc """
  Example Live view: a simple counter.

  Demonstrates the full Sigil.Live stack:
  - Server-rendered HTML on first load
  - WebSocket connection for real-time updates
  - DOM diffing on button clicks
  """
  use Sigil.Live

  @impl true
  def mount(_params, socket) do
    {:ok, Sigil.Live.assign(socket, count: 0, page_title: "Counter")}
  end

  @impl true
  def render(assigns) do
    """
    <div class="counter">
      <h1>Counter: #{assigns.count}</h1>
      <div class="buttons">
        <button sigil-click="decrement">−</button>
        <button sigil-click="increment">+</button>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("increment", _params, socket) do
    {:noreply, Sigil.Live.assign(socket, :count, socket.assigns.count + 1)}
  end

  def handle_event("decrement", _params, socket) do
    {:noreply, Sigil.Live.assign(socket, :count, socket.assigns.count - 1)}
  end
end
