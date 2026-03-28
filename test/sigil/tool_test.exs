defmodule Sigil.ToolTest do
  use ExUnit.Case, async: true

  defmodule EchoTool do
    use Sigil.Tool

    @impl true
    def name, do: "echo"

    @impl true
    def description, do: "Echoes input back"

    @impl true
    def params do
      %{
        "type" => "object",
        "properties" => %{
          "message" => %{"type" => "string"}
        },
        "required" => ["message"]
      }
    end

    @impl true
    def call(%{"message" => msg}, _context), do: {:ok, msg}
  end

  defmodule SlowTool do
    use Sigil.Tool

    @impl true
    def name, do: "slow"
    @impl true
    def description, do: "Takes too long"
    @impl true
    def params, do: %{"type" => "object", "properties" => %{}}
    @impl true
    def timeout, do: 100

    @impl true
    def call(_params, _context) do
      Process.sleep(500)
      {:ok, "done"}
    end
  end

  defmodule ProtectedTool do
    use Sigil.Tool

    @impl true
    def name, do: "protected"
    @impl true
    def description, do: "Requires approval"
    @impl true
    def params, do: %{"type" => "object", "properties" => %{}}
    @impl true
    def permission, do: :human_approval

    @impl true
    def call(_params, _context), do: {:ok, "executed"}
  end

  defmodule DisabledTool do
    use Sigil.Tool

    @impl true
    def name, do: "disabled"
    @impl true
    def description, do: "Cannot be called"
    @impl true
    def params, do: %{"type" => "object", "properties" => %{}}
    @impl true
    def permission, do: :disabled

    @impl true
    def call(_params, _context), do: {:ok, "should not run"}
  end

  describe "Tool.execute/3" do
    test "executes a tool and returns the result" do
      assert {:ok, "hello"} = Sigil.Tool.execute(EchoTool, %{"message" => "hello"})
    end

    test "times out slow tools" do
      assert {:error, :timeout} = Sigil.Tool.execute(SlowTool, %{})
    end

    test "requires approval for protected tools" do
      assert {:approval_required, ProtectedTool, %{}} =
               Sigil.Tool.execute(ProtectedTool, %{})
    end

    test "rejects disabled tools" do
      assert {:error, :tool_disabled} = Sigil.Tool.execute(DisabledTool, %{})
    end
  end

  describe "Tool behaviour defaults" do
    test "default permission is :auto" do
      assert EchoTool.permission() == :auto
    end

    test "default timeout is 30_000" do
      assert EchoTool.timeout() == 30_000
    end
  end
end
