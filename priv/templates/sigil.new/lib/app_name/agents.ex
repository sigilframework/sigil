defmodule Journal.Agents do
  @moduledoc "Context for managing agent configurations."

  import Ecto.Query
  alias Journal.{Repo, AgentConfig}

  def list_agents do
    from(a in AgentConfig, order_by: [asc: a.name])
    |> Repo.all()
  end

  def list_active_agents do
    from(a in AgentConfig,
      where: a.active == true,
      order_by: [asc: a.name]
    )
    |> Repo.all()
  end

  def get_agent!(id), do: Repo.get!(AgentConfig, id)

  def get_agent_by_slug!(slug), do: Repo.get_by!(AgentConfig, slug: slug)

  def create_agent(attrs) do
    %AgentConfig{}
    |> AgentConfig.changeset(attrs)
    |> Repo.insert()
  end

  def update_agent(%AgentConfig{} = agent, attrs) do
    agent
    |> AgentConfig.changeset(attrs)
    |> Repo.update()
  end

  def delete_agent(%AgentConfig{} = agent) do
    Repo.delete(agent)
  end
end
