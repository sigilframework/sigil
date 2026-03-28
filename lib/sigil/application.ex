defmodule Sigil.Application do
  @moduledoc """
  The Sigil framework supervision tree.

  Starts core services that are always available, and conditionally
  starts optional services when their dependencies are present:
  - Memory session store (ETS) — always
  - Agent runner supervisor — always
  - Live session store (ETS) — always
  - Repo (PostgreSQL) — when ecto_sql + postgrex are available and configured
  - Event store writer — when Repo is available
  - Web server (Bandit) — when bandit is available and port is configured
  """
  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        # ETS-based Live view session store with TTL cleanup
        Sigil.Live.SessionStore,
        # ETS-based session memory
        Sigil.Memory.Session,
        # Dynamic supervisor for agent processes
        {DynamicSupervisor, name: Sigil.Agent.Runner, strategy: :one_for_one}
      ]
      |> maybe_add_repo()
      |> maybe_add_event_store()
      |> maybe_add_web()

    opts = [strategy: :one_for_one, name: Sigil.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_add_repo(children) do
    if Code.ensure_loaded?(Ecto) and Application.get_env(:sigil, Sigil.Repo) do
      [Sigil.Repo | children]
    else
      children
    end
  end

  defp maybe_add_event_store(children) do
    if Code.ensure_loaded?(Ecto) and Application.get_env(:sigil, Sigil.Repo) do
      children ++ [Sigil.Agent.EventStore.Writer]
    else
      children
    end
  end

  defp maybe_add_web(children) do
    if Code.ensure_loaded?(Bandit) do
      if port = Application.get_env(:sigil, :port) do
        router = Application.get_env(:sigil, :router)

        if router do
          children ++ [{Bandit, plug: router, port: port}]
        else
          children
        end
      else
        children
      end
    else
      children
    end
  end
end
