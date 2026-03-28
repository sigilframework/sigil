defmodule Sigil.Dev.Watcher do
  @moduledoc """
  File system watcher for development.

  Watches `lib/` for changes and triggers recompilation.
  Only started in dev mode when `file_system` is available.

  ## Usage

  Add to your application supervision tree in dev:

      if Mix.env() == :dev do
        children ++ [Sigil.Dev.Watcher]
      end
  """
  use GenServer
  require Logger

  @watched_dirs ["lib"]
  @debounce_ms 300

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    if Code.ensure_loaded?(FileSystem) do
      {:ok, pid} = FileSystem.start_link(dirs: resolve_dirs())
      FileSystem.subscribe(pid)
      Logger.info("[Sigil.Dev] File watcher started — watching #{inspect(@watched_dirs)}")
      {:ok, %{fs_pid: pid, timer: nil}}
    else
      Logger.warning("[Sigil.Dev] file_system not available, skipping watcher")
      :ignore
    end
  end

  @impl true
  def handle_info({:file_event, _pid, {path, _events}}, state) do
    if watchable?(path) do
      # Debounce rapid file changes
      if state.timer, do: Process.cancel_timer(state.timer)
      timer = Process.send_after(self(), :recompile, @debounce_ms)
      {:noreply, %{state | timer: timer}}
    else
      {:noreply, state}
    end
  end

  def handle_info(:recompile, state) do
    Logger.info("[Sigil.Dev] File changed — recompiling...")

    case IEx.Helpers.recompile() do
      {:ok, modules} ->
        Logger.info("[Sigil.Dev] Recompiled #{length(modules)} module(s)")

      {:error, _} ->
        Logger.warning("[Sigil.Dev] Recompilation failed — check for errors")

      :noop ->
        :ok
    end

    {:noreply, %{state | timer: nil}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp resolve_dirs do
    @watched_dirs
    |> Enum.map(&Path.expand/1)
    |> Enum.filter(&File.dir?/1)
  end

  defp watchable?(path) do
    ext = Path.extname(path)
    ext in [".ex", ".eex", ".leex", ".heex", ".html"]
  end
end
