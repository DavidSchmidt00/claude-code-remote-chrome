#!/bin/bash
set -e

if [ -n "$CLAUDE_CREDENTIALS" ]; then
    mkdir -p ~/.claude
    echo "$CLAUDE_CREDENTIALS" > ~/.claude/.credentials.json
fi

# Install fake chrome-native-host (expected by Claude Code, not used by MCP)
mkdir -p ~/.claude/chrome
cat > ~/.claude/chrome/chrome-native-host << 'EOF'
#!/bin/bash
exec node /home/claude/chrome-native-host.js
EOF
chmod +x ~/.claude/chrome/chrome-native-host

# Start socat bridge: Unix socket -> TCP to host bridge
SOCK_DIR="/tmp/claude-mcp-browser-bridge-${USER}"
mkdir -p -m 700 "$SOCK_DIR"
SOCK_PATH="${SOCK_DIR}/$$.sock"
setsid socat UNIX-LISTEN:"$SOCK_PATH",mode=600,fork TCP:host.docker.internal:"${BRIDGE_PORT:-9229}" &

exec "$@"
