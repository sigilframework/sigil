#!/bin/sh
# Sigil Demo — Try a full AI app in 30 seconds
# Usage: curl -sL https://raw.githubusercontent.com/sigilframework/sigil/main/demo/start.sh | bash
set -e

echo ""
echo "  ⚡ Sigil Demo Installer"
echo "  ─────────────────────────────────"
echo ""

# Check for Docker
if ! command -v docker >/dev/null 2>&1; then
  echo "  ✗ Docker is required but not installed."
  echo "    Install it from https://docker.com/get-started"
  exit 1
fi

# Check for docker compose
if ! docker compose version >/dev/null 2>&1; then
  echo "  ✗ Docker Compose is required but not found."
  echo "    It's included with Docker Desktop."
  exit 1
fi

echo "  ✓ Docker found"

# Create temp directory
DEMO_DIR=$(mktemp -d)
echo "  ✓ Working directory: $DEMO_DIR"

# Download docker-compose.yml
curl -sL https://raw.githubusercontent.com/sigilframework/sigil/main/demo/docker-compose.yml -o "$DEMO_DIR/docker-compose.yml"
echo "  ✓ Downloaded config"

# Optional: API key
echo ""
echo "  Optional: Enter your Anthropic API key for AI chat"
echo "  (press Enter to skip — blog and admin will still work)"
printf "  API key: "
read -r api_key

echo ""
echo "  Starting Sigil Demo..."
echo ""

cd "$DEMO_DIR"

if [ -n "$api_key" ]; then
  ANTHROPIC_API_KEY="$api_key" docker compose up
else
  docker compose up
fi
