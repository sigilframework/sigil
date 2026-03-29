defmodule Mix.Tasks.Sigil.Server do
  @moduledoc """
  Start the Sigil dev server with auto-reload.

      mix sigil.server

  This starts the application with Bandit serving on the configured port
  (default: 4000). In dev mode, it also starts the file watcher for
  automatic recompilation when `.ex` files change.

  Automatically loads environment variables from `.env` if the file exists.
  """
  use Mix.Task

  @impl true
  def run(_args) do
    load_dot_env()

    # Start the file watcher if file_system is available
    if Code.ensure_loaded?(FileSystem) do
      Sigil.Dev.Watcher.start_link()
    end

    Mix.Task.run("run", ["--no-halt"])
  end

  defp load_dot_env do
    if File.exists?(".env") do
      ".env"
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.each(fn line ->
        line = String.trim(line)

        unless line == "" or String.starts_with?(line, "#") do
          case String.split(line, "=", parts: 2) do
            [key, value] ->
              key = String.trim(key)
              value = String.trim(value)

              # Only set if not already set (system env takes precedence)
              if System.get_env(key) == nil and value != "" do
                System.put_env(key, value)
              end

            _ ->
              :ok
          end
        end
      end)
    end
  end
end
