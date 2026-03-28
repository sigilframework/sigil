defmodule Sigil.Tool do
  @moduledoc """
  Behaviour for defining tools that AI agents can use.

  Tools are actions the agent can take — calling APIs, querying databases,
  sending emails, etc. Each tool defines its parameters, permissions,
  and execution logic.

  ## Defining a Tool

      defmodule MyApp.Tools.SendEmail do
        use Sigil.Tool

        @impl true
        def name, do: "send_email"

        @impl true
        def description, do: "Send an email to a recipient"

        @impl true
        def params do
          %{
            "type" => "object",
            "properties" => %{
              "to" => %{"type" => "string", "description" => "Recipient email"},
              "subject" => %{"type" => "string", "description" => "Email subject"},
              "body" => %{"type" => "string", "description" => "Email body"}
            },
            "required" => ["to", "subject", "body"]
          }
        end

        @impl true
        def call(%{"to" => to, "subject" => subject, "body" => body}, _context) do
          # Send the email
          {:ok, "Email sent to \#{to}"}
        end
      end

  ## Permissions

  Tools can require human approval before execution:

  - `:auto` — Execute immediately (default)
  - `:human_approval` — Pause and wait for human approval
  - `:disabled` — Tool is registered but cannot be called
  """

  @type permission :: :auto | :human_approval | :disabled

  @doc "A unique name for the tool (used in LLM function calling)."
  @callback name() :: String.t()

  @doc "A human-readable description of what the tool does."
  @callback description() :: String.t()

  @doc "JSON Schema describing the tool's input parameters."
  @callback params() :: map()

  @doc "Execute the tool with the given parameters and context."
  @callback call(params :: map(), context :: map()) ::
              {:ok, term()} | {:error, term()}

  @doc "Permission level for this tool. Default: `:auto`."
  @callback permission() :: permission()

  @doc "Timeout in milliseconds for tool execution. Default: `30_000`."
  @callback timeout() :: pos_integer()

  @optional_callbacks [permission: 0, timeout: 0]

  defmacro __using__(_opts) do
    quote do
      @behaviour Sigil.Tool

      @impl Sigil.Tool
      def permission, do: :auto

      @impl Sigil.Tool
      def timeout, do: 30_000

      defoverridable permission: 0, timeout: 0
    end
  end

  @doc """
  Execute a tool with timeout and permission checking.

  Returns `{:ok, result}`, `{:error, reason}`, or `{:approval_required, tool, params}`.
  """
  def execute(tool_module, params, context \\ %{}) do
    case tool_module.permission() do
      :disabled ->
        {:error, :tool_disabled}

      :human_approval ->
        {:approval_required, tool_module, params}

      :auto ->
        run_with_timeout(tool_module, params, context)
    end
  end

  defp run_with_timeout(tool_module, params, context) do
    timeout = tool_module.timeout()

    task =
      Task.async(fn ->
        try do
          tool_module.call(params, context)
        rescue
          e -> {:error, Exception.message(e)}
        end
      end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} ->
        :telemetry.execute(
          [:sigil, :tool, :call],
          %{duration: System.monotonic_time()},
          %{tool: tool_module.name()}
        )

        result

      nil ->
        {:error, :timeout}
    end
  end
end
