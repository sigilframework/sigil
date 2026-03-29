defmodule Journal.Application do
  use Application

  @impl true
  def start(_type, _args) do
    # Start :pg scope for conversation real-time sync
    :pg.start_link(:journal_conversations)

    children = [
      Journal.Repo,
      {Bandit, plug: Journal.Router, port: 4000}
    ]

    opts = [strategy: :one_for_one, name: Journal.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
