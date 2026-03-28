# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-03-28

### Added

#### Agent Framework (Layers 1–4)
- `Sigil.LLM` — Unified LLM interface with Anthropic and OpenAI adapters
- `Sigil.Tool` — Tool definition behaviour with permissions (`:auto`, `:human_approval`), timeouts, and JSON schema params
- `Sigil.Memory.Budget` — Token budget allocation across system prompt, tools, history, and response
- `Sigil.Memory.Context` — 4 context compaction strategies: `:sliding_window`, `:drop_tool_results`, `:summarize_oldest`, `:progressive`
- `Sigil.Memory.Tokenizer` — Approximate token counting with model-aware multipliers
- `Sigil.Memory.Summarizer` — LLM-powered progressive summarization with caching
- `Sigil.Agent` — GenServer orchestrator with think→act→observe loop
- `Sigil.Agent.EventStore` — Append-only event log for full audit trails
- `Sigil.Agent.Checkpoint` — Periodic state snapshots for durable execution
- `Sigil.Agent.Observer` — Timeline and context inspection for debugging
- `Sigil.Agent.Guard` — Token and turn budget enforcement
- `Sigil.Agent.Team` — Multi-agent orchestration with shared memory
- `Sigil.Agent.Telemetry` — `:telemetry` event emission for monitoring

#### Web Layer (Layer 5) — Optional
- `Sigil.Router` — Plug-based routing DSL with `live/3` macro
- `Sigil.Live` — Server-rendered real-time views over WebSocket
- `Sigil.Live.Diff` — Server-side DOM diffing with targeted patches
- `Sigil.Live.Channel` — WebSocket handler with CSRF verification
- `Sigil.Live.SessionStore` — ETS-backed session store with TTL cleanup
- `Sigil.Live.Handler` — HTTP handler for initial Live view renders
- `Sigil.Layout` — Layout system with default HTML shell
- `Sigil.Web.Static` — Static asset serving
- `Sigil.CSRF` — HMAC-SHA256 CSRF protection
- `sigil.js` — ~2KB client runtime (WebSocket, event delegation, DOM patching)

#### Auth — Optional
- `Sigil.Auth` — Registration, login, user lookup
- `Sigil.Auth.Password` — bcrypt password hashing (timing-safe)
- `Sigil.Auth.SessionPlug` — Plug-based session management
- `Sigil.Auth.User` — Ecto schema with email/password changeset

#### Developer Tools
- `mix sigil.server` — Dev server with file watching and auto-reload
- `mix sigil.gen` — AI-powered code generation from natural language
- `mix sigil.gen.agent` — AI-powered agent scaffolding
- `mix sigil.tailwind` — Tailwind CSS integration

#### Project Generator (separate package: `sigil_new`)
- `mix sigil.new` — Generate production-ready Sigil applications with Docker/Render.com support
