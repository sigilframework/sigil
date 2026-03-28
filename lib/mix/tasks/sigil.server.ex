defmodule Mix.Tasks.Sigil.Server do
  @moduledoc """
  Start the Sigil dev server.

      mix sigil.server

  This starts the application with Bandit serving on the configured port
  (default: 4000).
  """
  use Mix.Task

  @impl true
  def run(_args) do
    Mix.Task.run("run", ["--no-halt"])
  end
end
