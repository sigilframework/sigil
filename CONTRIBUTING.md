# Contributing to Sigil

Thanks for your interest in contributing to Sigil! Whether it's a bug fix, new feature, documentation improvement, or a question — you're welcome here.

## Quick Start

```bash
git clone https://github.com/sigilframework/sigil.git
cd sigil
mix deps.get
mix test
```

To test the example app generator:

```bash
mix sigil.new test_app
cd test_app
mix setup        # deps, DB, migrations, seeds
mix sigil.server  # http://localhost:4000
```

## How to Contribute

### Report a Bug

Open a [GitHub Issue](https://github.com/sigilframework/sigil/issues/new) with:
- What you expected to happen
- What actually happened
- Steps to reproduce
- Elixir/OTP version (`elixir --version`)

### Suggest a Feature

Start a [GitHub Discussion](https://github.com/sigilframework/sigil/discussions/new?category=ideas) first. This lets us talk through the design before you invest time writing code.

### Submit a Pull Request

1. Fork the repo
2. Create a branch (`git checkout -b my-change`)
3. Make your changes
4. Run the tests (`mix test`)
5. Ensure zero warnings (`mix compile --warnings-as-errors`)
6. Commit with a clear message
7. Open a PR

### Good First Issues

Look for issues labeled [`good first issue`](https://github.com/sigilframework/sigil/labels/good%20first%20issue). These are scoped, well-defined tasks that don't require deep framework knowledge.

## Project Structure

```
sigil/                     # The framework (Hex package)
├── lib/sigil/
│   ├── llm/               # LLM adapters (Anthropic, OpenAI)
│   ├── tool.ex            # Tool behaviour
│   ├── agent/             # Agent orchestration, teams, events
│   ├── memory/            # Context window management
│   ├── live/              # Real-time UI (WebSocket, DOM diffing)
│   └── auth/              # Authentication
├── lib/mix/tasks/         # Mix tasks (sigil.new, sigil.server, sigil.gen)
└── priv/templates/        # App generator templates (source of truth)
```

## Guidelines

### Code Style

- Run `mix format` before committing
- No warnings — we compile with `--warnings-as-errors`
- No debug statements (`IO.inspect`, `dbg`) in committed code
- Write `@moduledoc` for public modules

### Commits

- Use clear, imperative commit messages: "Add tool timeout configuration" not "added stuff"
- One logical change per commit

### Tests

- Add tests for new features
- Don't break existing tests
- Run the full suite: `mix test`

### Documentation

- Update `@moduledoc` and `@doc` when changing public APIs
- If you change the generator, test with `mix sigil.new test_app`

## Areas Where We Need Help

| Area | What's needed |
|------|--------------|
| **LLM Providers** | OpenAI adapter, Ollama local models |
| **Tools** | Pre-built tools (Stripe, GitHub, email, Slack) |
| **Documentation** | Guides, tutorials, API docs |
| **Testing** | More test coverage across all layers |
| **Templates** | Agent templates for common use cases |
| **Examples** | More generator templates for different use cases |

## New to Elixir?

That's fine — many contributors start here. These resources will get you up to speed:

- [Elixir Getting Started](https://elixir-lang.org/getting-started/introduction.html) — takes an afternoon
- [Elixir School](https://elixirschool.com) — practical lessons
- [Phoenix Guides](https://hexdocs.pm/phoenix/overview.html) — helpful context (Sigil.Live is inspired by LiveView)

Ask questions in [Discord](https://discord.com/channels/1487814726950981674/1487814838066483221) — we're happy to help.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
