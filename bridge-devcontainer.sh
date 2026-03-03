#!/usr/bin/env bash
# bridge-devcontainer.sh — start the socat bridge inside the devcontainer
# Run this once before `claude --chrome` to connect to the host's bridge-host.ps1

set -euo pipefail

BRIDGE_PORT="${BRIDGE_PORT:-9229}"
BRIDGE_HOST="host.docker.internal"
USER_NAME="$(whoami)"
SOCK_DIR="/tmp/claude-mcp-browser-bridge-${USER_NAME}"

# ── 1. Install socat if missing ───────────────────────────────────────────────
if ! command -v socat &>/dev/null; then
  echo "[bridge] socat not found — installing..."
  sudo apt-get install -y --quiet socat
fi

# ── 2. Install fake chrome-native-host (Claude Code checks for this) ──────────
NATIVE_HOST="${HOME}/.claude/chrome/chrome-native-host"
if [[ ! -x "$NATIVE_HOST" ]]; then
  echo "[bridge] Installing fake chrome-native-host..."
  mkdir -p "$(dirname "$NATIVE_HOST")"
  cat > "$NATIVE_HOST" << 'EOF'
#!/usr/bin/env bash
# Stub: Claude Code extension detection only.
# Actual browser comms go through the MCP Unix socket bridge.
exec cat
EOF
  chmod +x "$NATIVE_HOST"
fi
echo "[bridge] chrome-native-host v"

# ── 3. Clean up stale socket files ───────────────────────────────────────────
mkdir -p -m 700 "$SOCK_DIR"
find "$SOCK_DIR" -name '*.sock' -delete 2>/dev/null || true

# ── 4. Verify host is reachable on the bridge port ───────────────────────────
echo "[bridge] Checking ${BRIDGE_HOST}:${BRIDGE_PORT}..."
if ! timeout 2 bash -c "echo >/dev/tcp/${BRIDGE_HOST}/${BRIDGE_PORT}" 2>/dev/null; then
  echo ""
  echo "  ERROR: Cannot reach ${BRIDGE_HOST}:${BRIDGE_PORT}"
  echo ""
  echo "  Make sure bridge-host.ps1 is running on your Windows host:"
  echo "    pwsh -ExecutionPolicy Bypass -File bridge-host.ps1 -BridgeHost '::'"
  echo ""
  exit 1
fi
echo "[bridge] Host reachable v"

# ── 5. Start socat in background ─────────────────────────────────────────────
SOCK_PATH="${SOCK_DIR}/$$.sock"
setsid socat \
  UNIX-LISTEN:"${SOCK_PATH}",mode=600,fork \
  TCP:${BRIDGE_HOST}:${BRIDGE_PORT} &

SOCAT_PID=$!
sleep 0.5

# ── 6. Confirm it's still running ────────────────────────────────────────────
if ! kill -0 "$SOCAT_PID" 2>/dev/null; then
  echo ""
  echo "  ERROR: socat exited immediately."
  echo "  Check that bridge-host.ps1 is running with -BridgeHost '::'"
  echo ""
  exit 1
fi

echo "[bridge] socat bridge running (PID $SOCAT_PID)"
echo "[bridge] Socket: $SOCK_PATH"
echo ""
echo "  Ready — run: claude --chrome"
