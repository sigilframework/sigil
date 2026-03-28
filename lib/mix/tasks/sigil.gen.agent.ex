defmodule Mix.Tasks.Sigil.Gen.Agent do
  @moduledoc """
  Generate a new AI agent with a Live view for interaction.

  ## Usage

      mix sigil.gen.agent ContentWriter "writes blog posts in my style"
      mix sigil.gen.agent CodeReviewer "reviews pull requests"

  This generates:
  - An agent module (`lib/your_app/agents/content_writer.ex`)
  - A Live view for chatting with the agent (`lib/your_app_web/pages/content_writer_live.ex`)
  - Router entry instruction
  """
  use Mix.Task

  @impl true
  def run([]) do
    Mix.shell().error("""
    Usage: mix sigil.gen.agent AgentName "description"

    Example: mix sigil.gen.agent ContentWriter "writes blog posts in my style"
    """)
  end

  def run([name | desc_parts]) do
    description = Enum.join(desc_parts, " ")
    app_module = detect_app_module()
    app_name = Macro.underscore(app_module)
    agent_module_name = Macro.camelize(name)
    agent_file_name = Macro.underscore(name)

    Mix.shell().info("\n⚡ Generating agent: #{agent_module_name}\n")

    # Generate agent module
    agent_path = "lib/#{app_name}/agents/#{agent_file_name}.ex"
    agent_code = agent_template(app_module, agent_module_name, description)

    # Generate Live view
    live_path = "lib/#{app_name}_web/pages/#{agent_file_name}_live.ex"
    live_code = live_template(app_module, agent_module_name, agent_file_name)

    files = [{agent_path, agent_code}, {live_path, live_code}]

    for {path, code} <- files do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, code)
      Mix.shell().info("  #{IO.ANSI.green()}✓#{IO.ANSI.reset()} #{path}")
    end

    Mix.shell().info("""

    ✅ Agent generated!

    Add this route to your router:

        live "/#{agent_file_name}", #{app_module}Web.#{agent_module_name}Live

    Then configure your API key:

        config :sigil, :gen,
          api_key: System.get_env("ANTHROPIC_API_KEY")
    """)
  end

  defp agent_template(app_module, agent_name, description) do
    """
    defmodule #{app_module}.Agents.#{agent_name} do
      @moduledoc \"\"\"
      #{agent_name} agent — #{description}
      \"\"\"
      use Sigil.Agent

      @impl true
      def init_agent(_opts) do
        %{
          llm: {Sigil.LLM.Anthropic, model: "claude-sonnet-4-20250514"},
          tools: [],
          system: \"\"\"
          You are #{agent_name}, an AI assistant that #{description}.
          Be concise, helpful, and professional.
          \"\"\",
          memory: :sliding_window,
          max_turns: 50
        }
      end
    end
    """
  end

  defp live_template(app_module, agent_name, _agent_file_name) do
    """
    defmodule #{app_module}Web.#{agent_name}Live do
      @moduledoc \"\"\"
      Chat interface for the #{agent_name} agent.
      \"\"\"
      use Sigil.Live

      @impl true
      def mount(_params, socket) do
        {:ok, Sigil.Live.assign(socket,
          page_title: "#{agent_name}",
          messages: [],
          input: "",
          loading: false,
          agent_pid: nil
        )}
      end

      @impl true
      def render(assigns) do
        messages_html = Enum.map_join(assigns.messages, "", fn msg ->
          role_class = if msg.role == "user", do: "bg-gray-800", else: "bg-purple-900/30 border border-purple-800/50"
          role_label = if msg.role == "user", do: "You", else: "#{agent_name}"

          \"\"\"
          <div class=\\"\#{role_class} rounded-lg p-4\\">
            <div class=\\"text-sm font-semibold text-gray-400 mb-1\\">\#{role_label}</div>
            <div class=\\"text-gray-100\\">\#{msg.content}</div>
          </div>
          \"\"\"
        end)

        loading_html = if assigns.loading do
          \\"<div class=\\\\"text-purple-400 animate-pulse\\\\">Thinking...</div>\\"
        else
          ""
        end

        \"\"\"
        <div class=\\"space-y-6\\">
          <h1 class=\\"text-3xl font-bold\\">#{agent_name}</h1>

          <div class=\\"space-y-4 min-h-[300px]\\">
            \#{messages_html}
            \#{loading_html}
          </div>

          <form sigil-submit=\\"send_message\\" class=\\"flex gap-2\\">
            <input type=\\"text\\" name=\\"message\\" placeholder=\\"Type a message...\\"
                   class=\\"flex-1 bg-gray-800 rounded-lg px-4 py-2 text-white border border-gray-700 focus:border-purple-500 focus:outline-none\\"
                   autocomplete=\\"off\\" />
            <button type=\\"submit\\"
                    class=\\"bg-purple-600 hover:bg-purple-500 text-white px-6 py-2 rounded-lg transition\\">
              Send
            </button>
          </form>
        </div>
        \"\"\"
      end

      @impl true
      def handle_event("send_message", %{"message" => message}, socket) when message != "" do
        # Add user message
        messages = socket.assigns.messages ++ [%{role: "user", content: message}]
        socket = Sigil.Live.assign(socket, messages: messages, input: "", loading: true)

        # Start or reuse agent
        {agent_pid, socket} = ensure_agent(socket)

        # Send message to agent in background
        parent = self()
        Task.start(fn ->
          case Sigil.Agent.chat(agent_pid, message) do
            {:ok, response} ->
              send(parent, {:agent_response, response})

            {:error, reason} ->
              send(parent, {:agent_error, reason})
          end
        end)

        {:noreply, socket}
      end

      def handle_event("send_message", _params, socket) do
        {:noreply, socket}
      end

      @impl true
      def handle_info({:agent_response, response}, socket) do
        content = if is_binary(response), do: response, else: Map.get(response, :content, inspect(response))
        messages = socket.assigns.messages ++ [%{role: "assistant", content: content}]
        {:noreply, Sigil.Live.assign(socket, messages: messages, loading: false)}
      end

      def handle_info({:agent_error, reason}, socket) do
        messages = socket.assigns.messages ++ [%{role: "assistant", content: "Error: \#{inspect(reason)}"}]
        {:noreply, Sigil.Live.assign(socket, messages: messages, loading: false)}
      end

      defp ensure_agent(socket) do
        if socket.assigns.agent_pid && Process.alive?(socket.assigns.agent_pid) do
          {socket.assigns.agent_pid, socket}
        else
          api_key = Application.get_env(:sigil, :gen, []) |> Keyword.get(:api_key, System.get_env("ANTHROPIC_API_KEY"))
          {:ok, pid} = Sigil.Agent.start(#{app_module}.Agents.#{agent_name}, api_key: api_key)
          {pid, Sigil.Live.assign(socket, :agent_pid, pid)}
        end
      end
    end
    """
  end

  defp detect_app_module do
    case Mix.Project.get() do
      nil -> "MyApp"
      mod ->
        mod.project()[:app]
        |> Atom.to_string()
        |> Macro.camelize()
    end
  end
end
