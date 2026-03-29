defmodule Sigil.Agent.StateTest do
  use ExUnit.Case, async: true

  alias Sigil.Agent.State

  describe "token_usage struct" do
    test "initializes with zero usage" do
      state = %State{
        module: SomeModule,
        config: %{llm: {Sigil.LLM.Anthropic, []}},
        run_id: "test-run"
      }

      assert state.token_usage == %{input_tokens: 0, output_tokens: 0, total_tokens: 0}
    end

    test "usage can be accumulated" do
      state = %State{
        module: SomeModule,
        config: %{llm: {Sigil.LLM.Anthropic, []}},
        run_id: "test-run"
      }

      usage = %{input_tokens: 150, output_tokens: 50, total_tokens: 200}
      state = %{state | token_usage: usage}

      assert state.token_usage.input_tokens == 150
      assert state.token_usage.output_tokens == 50
      assert state.token_usage.total_tokens == 200
    end
  end
end
