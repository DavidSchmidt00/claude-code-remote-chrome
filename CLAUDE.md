# CLAUDE.md — Technical context for AI agents

## Architecture

Chrome Bridge is a transparent TCP proxy for Chrome Native Messaging Host (NMH) Unix sockets. It enables Claude Code's built-in MCP server (`claude --claude-in-chrome-mcp`) to communicate with Chrome running on the host from inside a Docker container.

### Data flow

```
Claude Code (container)
  → claude --claude-in-chrome-mcp (MCP server, spawned by Claude)
    → connects to Unix socket: /tmp/claude-mcp-browser-bridge-{USER}/{PID}.sock
      → bridge-container.js (forwards to TCP)
        → bridge-host.js (TCP :9229, forwards to real NMH socket)
          → /tmp/claude-mcp-browser-bridge-{host-user}/{NMH-PID}.sock
            → Chrome NMH → Chrome Extension → chrome.debugger API
```

### Protocol

Native Messaging framing on the Unix socket:
- **4 bytes** — message length (uint32, little-endian)
- **N bytes** — JSON payload (UTF-8)

Example command:
```json
{"method":"execute_tool","params":{"client_id":"claude-code","tool":"tabs_context_mcp","args":{"createIfEmpty":true}}}
```

The bridge does raw byte forwarding — no parsing or modification of messages.

### Key discovery: USER env var

Claude Code's MCP server resolves the socket directory name from the `USER` environment variable. Docker does NOT set `$USER` automatically from the Dockerfile `USER` directive. Without `ENV USER=claude` in the Dockerfile, the MCP server looks in `/tmp/claude-mcp-browser-bridge-unknown/` and never finds the bridge socket.

### Key discovery: Unix sockets don't work through OrbStack volume mounts

Socket files appear in `ls` but `connect()` returns `ECONNREFUSED`. This is why the TCP bridge is necessary.

### Key discovery: chrome-native-host is NOT used by MCP

The file `~/.claude/chrome/chrome-native-host` is created by Claude Code for Chrome's `connectNative()` API. The MCP server does NOT spawn it — it directly watches the socket directory. The entrypoint still creates this file because Claude Code expects it to exist.

## File overview

| File | Location | Purpose |
|------|----------|---------|
| `bridge-host.js` | Host | TCP server, connects to real NMH socket |
| `bridge-container.js` | Container | Creates fake NMH socket, forwards to TCP |
| `entrypoint.sh` | Container | Injects credentials, sets up chrome-native-host |
| `Dockerfile` | Build | node:20-slim, Claude CLI, user matching host UID |
| `docker-compose.yml` | Build | Mounts bridge, sets env vars |
| `Makefile` | Host | `up`, `shell` commands |

## Environment variables

| Variable | Where | Default | Purpose |
|----------|-------|---------|---------|
| `USER` | Dockerfile ENV | `claude` | Socket directory name |
| `BRIDGE_PORT` | docker-compose | `9229` | TCP port between bridges |
| `BRIDGE_TCP_HOST` | bridge-container.js | `host.docker.internal` | Host address from container |
| `BRIDGE_USER` | bridge-host.js | `os.userInfo().username` | Host socket directory name |
| `BRIDGE_HOST` | bridge-host.js | `0.0.0.0` | TCP bind address |
| `CLAUDE_CREDENTIALS` | .env.local | — | OAuth JSON for ~/.claude/.credentials.json |

## Testing

Use pytest for tests (reminder for project convention).

The original `test-socket.py` (now removed) was used to verify socket connectivity. To manually test the bridge:

```bash
# Container: send a test message through the bridge
python3 -c "
import socket, struct, json
s = socket.socket(socket.AF_UNIX)
s.settimeout(5)
s.connect('/tmp/claude-mcp-browser-bridge-claude/<PID>.sock')
msg = json.dumps({'method':'execute_tool','params':{'client_id':'test','tool':'tabs_context_mcp','args':{'createIfEmpty':True}}}).encode()
s.sendall(struct.pack('<I', len(msg)) + msg)
hdr = s.recv(4)
length = struct.unpack('<I', hdr)[0]
data = b''
while len(data) < length: data += s.recv(length - len(data))
print(json.dumps(json.loads(data), indent=2))
"
```

## Debugging

- MCP logs: `~/.cache/claude-cli-nodejs/-home-claude/mcp-logs-claude-in-chrome/*.jsonl`
- bridge-container.js logs to stderr (visible in terminal)
- bridge-host.js logs to stderr
- Use `strace -f -e trace=connect,openat -p <MCP_PID>` to trace MCP server (requires `SYS_PTRACE` capability in compose)
