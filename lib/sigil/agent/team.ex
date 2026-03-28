defmodule Sigil.Agent.Team do
  @moduledoc """
  A supervised group of agents that can communicate and share state.

  Teams provide:
  - **Shared memory** via a dedicated ETS table all agents can read/write
  - **Named agents** so agents can address each other by role
  - **Supervised execution** — if one agent crashes, others continue
  - **Message passing** between agents in the team

  ## Usage

      {:ok, team} = Sigil.Agent.Team.start(%{
        name: :research_team,
        agents: [
          {:researcher, ResearchAgent, [topic: "market analysis"]},
          {:analyst, AnalysisAgent, []},
          {:writer, ReportAgent, [format: :pdf]}
        ],
        shared_memory: true
      })

      # Send a message to a specific agent
      Sigil.Agent.Team.send_message(team, :researcher, "Find Q4 revenue data")

      # Broadcast to all agents
      Sigil.Agent.Team.broadcast(team, "New deadline: Friday")

      # Read from shared memory
      Sigil.Agent.Team.shared_get(team, :findings)

  ## Inside an Agent

  Agents can discover their team and peers:

      def on_complete(response, state) do
        {:ok, team} = Sigil.Agent.Team.lookup(state.opts[:team_name])
        Sigil.Agent.Team.shared_put(team, :research_results, response)
        Sigil.Agent.Team.send_message(team, :analyst, "Research complete")
        {:ok, response, state}
      end
  """

  alias Sigil.Agent.Message

  defstruct [:name, :supervisor_pid, :agents, :shared_table]

  @type t :: %__MODULE__{
          name: atom(),
          supervisor_pid: pid(),
          agents: %{atom() => pid()},
          shared_table: atom() | nil
        }

  @doc """
  Start a team of agents.

  ## Config

  - `:name` — Team name (atom, required)
  - `:agents` — List of `{name, module, opts}` tuples
  - `:shared_memory` — Whether to create a shared ETS table (default: true)
  """
  def start(config) when is_map(config) do
    name = Map.fetch!(config, :name)
    agent_specs = Map.get(config, :agents, [])
    shared_memory? = Map.get(config, :shared_memory, true)

    # Create shared ETS table if requested
    shared_table =
      if shared_memory? do
        table_name = :"sigil_team_#{name}"
        :ets.new(table_name, [:named_table, :public, :set, read_concurrency: true])
        table_name
      end

    # Start agents under a DynamicSupervisor
    {:ok, sup_pid} = DynamicSupervisor.start_link(
      strategy: :one_for_one,
      name: :"sigil_team_sup_#{name}"
    )

    # Start each agent as a child of the DynamicSupervisor
    agents =
      Enum.reduce(agent_specs, %{}, fn {agent_name, agent_module, agent_opts}, acc ->
        augmented_opts =
          agent_opts
          |> Keyword.put(:team_name, name)
          |> Keyword.put(:agent_name, agent_name)

        child_spec = %{
          id: {Sigil.Agent, agent_name},
          start: {Sigil.Agent, :start_link, [{agent_module, augmented_opts}]},
          restart: :temporary
        }

        case DynamicSupervisor.start_child(sup_pid, child_spec) do
          {:ok, pid} ->
            # Notify agent of its team membership
            send(pid, {:sigil_set_team, name, shared_table})
            Map.put(acc, agent_name, pid)

          {:error, reason} ->
            require Logger
            Logger.warning("Failed to start agent #{agent_name}: #{inspect(reason)}")
            acc
        end
      end)

    team = %__MODULE__{
      name: name,
      supervisor_pid: sup_pid,
      agents: agents,
      shared_table: shared_table
    }

    # Store team in a global registry so agents can find it
    :persistent_term.put({:sigil_team, name}, team)

    {:ok, team}
  end

  @doc "Send a message to a named agent in the team."
  def send_message(%__MODULE__{} = team, agent_name, content, opts \\ []) do
    case Map.get(team.agents, agent_name) do
      nil ->
        {:error, :agent_not_found}

      pid when is_pid(pid) ->
        if Process.alive?(pid) do
          from = Keyword.get(opts, :from, :team)
          message = Message.new(from, agent_name, content, opts)
          send(pid, {:sigil_agent_message, message})
          :ok
        else
          {:error, :agent_dead}
        end
    end
  end

  @doc "Broadcast a message to all agents in the team."
  def broadcast(%__MODULE__{} = team, content, opts \\ []) do
    Enum.each(team.agents, fn {agent_name, pid} ->
      if is_pid(pid) and Process.alive?(pid) do
        from = Keyword.get(opts, :from, :team)
        message = Message.new(from, agent_name, content, opts)
        send(pid, {:sigil_agent_message, message})
      end
    end)

    :ok
  end

  @doc "Get the PID of a named agent."
  def get_agent(%__MODULE__{} = team, agent_name) do
    Map.get(team.agents, agent_name)
  end

  @doc "List all agents and their status."
  def list_agents(%__MODULE__{} = team) do
    Enum.map(team.agents, fn {name, pid} ->
      %{
        name: name,
        pid: pid,
        alive: is_pid(pid) and Process.alive?(pid)
      }
    end)
  end

  # Shared memory operations

  @doc "Get a value from the team's shared memory."
  def shared_get(%__MODULE__{shared_table: table}, key) when not is_nil(table) do
    case :ets.lookup(table, key) do
      [{_, value}] -> {:ok, value}
      [] -> {:error, :not_found}
    end
  end

  def shared_get(_, _), do: {:error, :no_shared_memory}

  @doc "Put a value into the team's shared memory."
  def shared_put(%__MODULE__{shared_table: table}, key, value) when not is_nil(table) do
    :ets.insert(table, {key, value})
    :ok
  end

  def shared_put(_, _, _), do: {:error, :no_shared_memory}

  @doc "Delete a key from the team's shared memory."
  def shared_delete(%__MODULE__{shared_table: table}, key) when not is_nil(table) do
    :ets.delete(table, key)
    :ok
  end

  def shared_delete(_, _), do: {:error, :no_shared_memory}

  @doc "Get all key-value pairs from shared memory."
  def shared_all(%__MODULE__{shared_table: table}) when not is_nil(table) do
    :ets.tab2list(table) |> Map.new()
  end

  def shared_all(_), do: {:error, :no_shared_memory}

  @doc "Stop the team and all its agents."
  def stop(%__MODULE__{} = team) do
    # Clean up shared memory
    if team.shared_table do
      try do
        :ets.delete(team.shared_table)
      rescue
        ArgumentError -> :ok
      end
    end

    # Clean up persistent term
    try do
      :persistent_term.erase({:sigil_team, team.name})
    rescue
      ArgumentError -> :ok
    end

    # Stop the supervisor (kills all agents)
    if Process.alive?(team.supervisor_pid) do
      DynamicSupervisor.stop(team.supervisor_pid, :normal)
    end

    :ok
  end

  @doc """
  Look up a team by name.

  Agents can use this to find their team from inside callbacks.
  """
  def lookup(team_name) do
    try do
      {:ok, :persistent_term.get({:sigil_team, team_name})}
    rescue
      ArgumentError -> {:error, :team_not_found}
    end
  end
end
