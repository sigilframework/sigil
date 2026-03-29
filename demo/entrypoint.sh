#!/bin/sh
set -e

echo ""
echo "  ⚡ Sigil Demo"
echo "  ─────────────────────────────────"
echo ""

# Wait for database to be ready
echo "  Waiting for database..."
attempts=0
max_attempts=6
until bin/sigil_demo eval "SigilDemo.Release.migrate()" 2>/dev/null; do
  attempts=$((attempts + 1))
  if [ $attempts -ge $max_attempts ]; then
    echo "  Database not ready after ${max_attempts} attempts, trying migration anyway..."
    bin/sigil_demo eval "SigilDemo.Release.migrate()"
    break
  fi
  echo "  Database not ready, retrying in 5s... (attempt $attempts/$max_attempts)"
  sleep 5
done
echo "  ✓ Migrations complete."

echo "  Running seeds..."
bin/sigil_demo eval "SigilDemo.Release.seed()"
echo "  ✓ Seeds complete."

echo ""
echo "  ┌────────────────────────────────────────────────┐"
echo "  │                                                │"
echo "  │  ⚡ Sigil Demo running at http://localhost:4000 │"
echo "  │                                                │"
echo "  │  Admin: admin@example.com / admin123           │"
echo "  │                                                │"
echo "  └────────────────────────────────────────────────┘"
echo ""

if [ -z "$ANTHROPIC_API_KEY" ]; then
  echo "  ℹ  AI chat disabled (no ANTHROPIC_API_KEY set)"
  echo "  Add it with: docker compose up -e ANTHROPIC_API_KEY=sk-ant-..."
  echo ""
fi

exec bin/sigil_demo start
