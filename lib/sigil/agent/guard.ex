defmodule Sigil.Agent.Guard do
  @moduledoc """
  Input guardrails for agent messages.

  Checks for prompt injection attempts, validates input length,
  and sanitizes content before it reaches the LLM.

  ## Usage

      case Sigil.Agent.Guard.check(user_input) do
        :ok -> proceed
        {:error, reason} -> reject
      end
  """

  @max_input_length 50_000

  @doc """
  Run all guardrail checks on user input.

  Returns `:ok` or `{:error, reason}`.
  """
  def check(input, opts \\ []) do
    max_length = Keyword.get(opts, :max_length, @max_input_length)

    with :ok <- check_length(input, max_length),
         :ok <- check_injection(input) do
      :ok
    end
  end

  @doc "Check if input exceeds the maximum length."
  def check_length(input, max_length \\ @max_input_length) do
    if String.length(input) > max_length do
      {:error, :input_too_long}
    else
      :ok
    end
  end

  @doc """
  Check for common prompt injection patterns.

  This is a basic heuristic check — not a replacement for proper
  sandboxing and output validation.
  """
  def check_injection(input) do
    lowered = String.downcase(input)

    injection_patterns = [
      "ignore previous instructions",
      "ignore all prior",
      "disregard your instructions",
      "forget your system prompt",
      "you are now",
      "new instructions:",
      "override your",
      "system prompt:",
      "```system"
    ]

    if Enum.any?(injection_patterns, &String.contains?(lowered, &1)) do
      {:error, :potential_injection}
    else
      :ok
    end
  end

  @doc "Sanitize input by removing potentially dangerous content."
  def sanitize(input) do
    input
    |> String.trim()
    |> String.replace(~r/[\x00-\x08\x0B\x0C\x0E-\x1F]/, "")
  end
end
