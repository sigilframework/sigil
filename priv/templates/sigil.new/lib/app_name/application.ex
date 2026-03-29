defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    # Start :pg scope for conversation real-time sync
    :pg.start_link(:my_app_conversations)

    children = [
      MyApp.Repo,
      {Bandit, plug: MyApp.Router, port: 4000}
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
