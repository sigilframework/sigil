# Build stage: generate and compile a Sigil demo app
FROM elixir:1.18-slim AS build

RUN apt-get update && apt-get install -y git build-essential && rm -rf /var/lib/apt/lists/*

WORKDIR /build

ENV MIX_ENV=prod

# Install hex and rebar
RUN mix local.hex --force && mix local.rebar --force

# Install the Sigil framework from Hex
RUN mix archive.install hex sigil --force

# Generate the demo app
# Use 'yes ""' to skip the interactive API key prompt
RUN yes "" | mix sigil.new sigil_demo

WORKDIR /build/sigil_demo

# Install production dependencies
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy in production-ready runtime config (reads env vars at startup)
COPY config/runtime.exs config/runtime.exs

# Compile and build release
RUN mix compile
RUN mix release

# ============================================
# Runtime stage: minimal image
# ============================================
FROM debian:bookworm-slim AS runtime

RUN apt-get update && \
    apt-get install -y libssl3 libncurses6 locales ca-certificates curl && \
    rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8

WORKDIR /app

COPY --from=build /build/sigil_demo/_build/prod/rel/sigil_demo ./
COPY entrypoint.sh ./
RUN chmod +x entrypoint.sh

ENV PORT=4000
EXPOSE 4000

CMD ["sh", "entrypoint.sh"]
