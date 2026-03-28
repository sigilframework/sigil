defmodule Sigil.Examples.Router do
  @moduledoc """
  Example router demonstrating Sigil.Router DSL.
  """
  use Sigil.Router

  live "/", Sigil.Examples.CounterLive
  live "/counter", Sigil.Examples.CounterLive

  # Must be last — adds WebSocket endpoint, static serving, and 404
  sigil_routes()
end
