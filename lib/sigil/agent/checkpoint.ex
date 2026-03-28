if Code.ensure_loaded?(Ecto) do
defmodule Sigil.Agent.Checkpoint do
  @moduledoc """
  Periodic snapshots of agent state for durable execution.

  Checkpoints capture the full agent state — messages, config, turn count,
  custom state — along with the event sequence at time of capture. On resume,
  the agent loads the latest checkpoint and replays events since.

  ## Checkpoint Policy

  Checkpoints are created:
  - Every N turns (configurable, default: 5)
  - After every tool execution
  - Before context compaction (preserves pre-compaction state)
  - On explicit request via `Sigil.Agent.checkpoint(pid)`

  ## Resume

      # Resume from the latest checkpoint
      {:ok, pid} = Sigil.Agent.resume(run_id)

      # Resume from a specific checkpoint
      {:ok, pid} = Sigil.Agent.resume(run_id, checkpoint_id: "abc-123")

  ## Usage

      Checkpoint.save(run_id, state, messages, config, sequence)
      {:ok, checkpoint} = Checkpoint.latest(run_id)
      {:ok, checkpoint} = Checkpoint.load(checkpoint_id)
  """

  import Ecto.Query

  defmodule Schema do
    use Ecto.Schema

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "agent_checkpoints" do
      field :run_id, Ecto.UUID
      field :sequence, :integer
      field :state, :map
      field :messages, :map
      field :config, :map

      timestamps(type: :utc_datetime, updated_at: false)
    end
  end

  @doc """
  Save a checkpoint of the current agent state.

  The state is serialized to JSON-safe maps. Functions, PIDs, and
  other non-serializable terms are stripped or converted to strings.
  """
  def save(run_id, state, messages, config, sequence) do
    unless repo_available?() do
      {:ok, %{id: nil}}
    else
      checkpoint = %Schema{
        run_id: run_id,
        sequence: sequence,
        state: serialize_state(state),
        messages: %{"messages" => serialize_messages(messages)},
        config: serialize_config(config)
      }

      case repo().insert(checkpoint) do
        {:ok, saved} ->
          # Also record a checkpoint event
          Sigil.Agent.EventStore.append(run_id, :checkpoint_created, %{
            checkpoint_id: saved.id,
            sequence: sequence
          }, sequence: sequence + 1, agent_module: Map.get(state, :module) |> to_string())

          {:ok, saved}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @doc """
  Load the latest checkpoint for a run.
  """
  def latest(run_id) do
    query =
      from c in Schema,
        where: c.run_id == ^run_id,
        order_by: [desc: c.sequence],
        limit: 1

    case repo().one(query) do
      nil -> {:error, :no_checkpoint}
      checkpoint -> {:ok, deserialize_checkpoint(checkpoint)}
    end
  end

  @doc """
  Load a specific checkpoint by ID.
  """
  def load(checkpoint_id) do
    case repo().get(Schema, checkpoint_id) do
      nil -> {:error, :not_found}
      checkpoint -> {:ok, deserialize_checkpoint(checkpoint)}
    end
  end

  @doc """
  List all checkpoints for a run, most recent first.
  """
  def list(run_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    query =
      from c in Schema,
        where: c.run_id == ^run_id,
        order_by: [desc: c.sequence],
        limit: ^limit,
        select: %{
          id: c.id,
          run_id: c.run_id,
          sequence: c.sequence,
          inserted_at: c.inserted_at
        }

    repo().all(query)
  end

  @doc """
  Check if a checkpoint should be created based on the policy.

  Returns true if any of the checkpoint conditions are met.
  """
  def should_checkpoint?(state) do
    policy = Map.get(state, :checkpoint_policy, default_policy())
    turn = Map.get(state, :turn_count, 0)

    cond do
      # Every N turns
      policy[:every_n_turns] && turn > 0 && rem(turn, policy[:every_n_turns]) == 0 ->
        true

      # Flag set by tool execution
      Map.get(state, :checkpoint_after_tool) == true ->
        true

      # Flag set before compaction
      Map.get(state, :checkpoint_before_compaction) == true ->
        true

      true ->
        false
    end
  end

  @doc "Default checkpoint policy."
  def default_policy do
    %{
      every_n_turns: 5,
      after_tool_calls: true,
      before_compaction: true
    }
  end

  # Serialization

  defp serialize_state(state) when is_struct(state) do
    state
    |> Map.from_struct()
    |> Map.drop([:module, :budget, :config])
    |> Map.new(fn {k, v} -> {to_string(k), safe_serialize(v)} end)
  end

  defp serialize_state(state) when is_map(state) do
    state
    |> Map.drop([:module, :budget, :config])
    |> Map.new(fn {k, v} -> {to_string(k), safe_serialize(v)} end)
  end

  defp serialize_messages(messages) when is_list(messages) do
    Enum.map(messages, fn msg ->
      Map.new(msg, fn {k, v} -> {to_string(k), safe_serialize(v)} end)
    end)
  end

  defp serialize_config(config) when is_map(config) do
    config
    |> Map.new(fn {k, v} ->
      key = to_string(k)

      value =
        case {k, v} do
          {:llm, {adapter, opts}} ->
            %{"adapter" => to_string(adapter), "opts" => Keyword.new(opts) |> Map.new(fn {ok, ov} -> {to_string(ok), safe_serialize(ov)} end)}

          {:tools, tools} when is_list(tools) ->
            Enum.map(tools, &to_string/1)

          _ ->
            safe_serialize(v)
        end

      {key, value}
    end)
  end

  defp safe_serialize(v) when is_atom(v), do: to_string(v)
  defp safe_serialize(v) when is_binary(v), do: v
  defp safe_serialize(v) when is_number(v), do: v
  defp safe_serialize(v) when is_boolean(v), do: v
  defp safe_serialize(nil), do: nil
  defp safe_serialize(v) when is_pid(v), do: inspect(v)
  defp safe_serialize(v) when is_reference(v), do: inspect(v)
  defp safe_serialize(v) when is_function(v), do: inspect(v)
  defp safe_serialize(v) when is_list(v), do: Enum.map(v, &safe_serialize/1)

  defp safe_serialize(v) when is_map(v) do
    Map.new(v, fn {k, val} -> {to_string(k), safe_serialize(val)} end)
  end

  defp safe_serialize(v), do: inspect(v)

  defp deserialize_checkpoint(checkpoint) do
    %{
      id: checkpoint.id,
      run_id: checkpoint.run_id,
      sequence: checkpoint.sequence,
      state: checkpoint.state,
      messages: (checkpoint.messages["messages"] || []) |> deserialize_messages(),
      config: checkpoint.config,
      inserted_at: checkpoint.inserted_at
    }
  end

  defp deserialize_messages(messages) do
    Enum.map(messages, fn msg ->
      # Restore all fields, converting string keys back to atoms
      # This preserves tool_use_id, type, id, name, input etc.
      msg
      |> Enum.reduce(%{}, fn {k, v}, acc ->
        atom_key =
          case k do
            k when is_atom(k) -> k
            "role" -> :role
            "content" -> :content
            "type" -> :type
            "tool_use_id" -> :tool_use_id
            "id" -> :id
            "name" -> :name
            "input" -> :input
            "text" -> :text
            other -> String.to_atom(other)
          end

        Map.put(acc, atom_key, v)
      end)
    end)
  end

  defp repo do
    Application.get_env(:sigil, :repo, Sigil.Repo)
  end

  defp repo_available? do
    Application.get_env(:sigil, Sigil.Repo) != nil
  end
end
end
