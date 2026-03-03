# Chrome Bridge for Claude Code in Docker

Run Claude Code inside a Docker container while controlling Chrome on your host machine.

## What it does

Claude Code has a "Claude in Chrome" feature that lets it control your browser — navigate pages, fill forms, take screenshots, etc. Normally this only works when Claude Code runs directly on your machine. This project bridges that gap so Claude Code running in a container can talk to Chrome on your host.

## How it works

A socat bridge in the container and a script on the host forward messages between them:

```
Container                          Host
Claude Code                        Chrome
    |                                |
    v                                ^
socat (entrypoint)   --TCP:9229-->  bridge-host.js / bridge-host.ps1
(Unix socket)                      (Unix socket or Named Pipe)
```

## Prerequisites

- Docker (Docker Desktop, OrbStack, or similar)
- Chrome with the [Claude browser extension](https://claude.ai/chrome) installed
- Claude account credentials
- **Mac/Linux host:** Node.js (for `bridge-host.js`)
- **Windows host:** PowerShell 7+ (for `bridge-host.ps1`) — no Node.js needed

## Setup (Mac / Linux host)

1. **Create `.env.local`** with your credentials:

   ```
   CLAUDE_CREDENTIALS={"claudeAiOauth":{"accessToken":"...","refreshToken":"...","expiresAt":...}}
   ```

   You can find these in `~/.claude/.credentials.json` on your host.

2. **Build and start** the container:

   ```bash
   make up
   ```

3. **Start the host bridge** (separate terminal):

   ```bash
   node bridge-host.js
   ```

4. **Inside the container**, start Claude (the bridge starts automatically via entrypoint):

   ```bash
   claude --chrome
   ```

5. Ask Claude to do something in Chrome, e.g. `open google.com`.

## Setup (Windows host — VS Code Dev Containers)

On Windows, Claude Code uses a **Named Pipe** (`\\.\pipe\claude-mcp-browser-bridge-<user>`) instead of a Unix socket, so `bridge-host.js` won't work. Use `bridge-host.ps1` instead — no Node.js required.

### Additional prerequisites

- PowerShell 7+: `winget install Microsoft.PowerShell`
- Claude Code installed on Windows (registers the Chrome Native Messaging Host):
  ```powershell
  npm install -g @anthropic-ai/claude-code
  ```

### Steps

1. **Start Claude with Chrome on Windows** to activate the Named Pipe (keep this terminal open):

   ```powershell
   claude --chrome
   ```

2. **Start the PowerShell bridge** (separate terminal):

   ```powershell
   # -BridgeHost '::' is required on WSL2: Dev Containers resolve
   # host.docker.internal as an IPv6 address
   pwsh -ExecutionPolicy Bypass -File bridge-host.ps1 -BridgeHost '::'
   ```

3. **Inside the Dev Container**, run the helper script once:

   ```bash
   bash bridge-devcontainer.sh
   ```

   This installs socat, sets up the required `chrome-native-host` stub, and starts the socat bridge.

4. **Inside the Dev Container**, start Claude:

   ```bash
   claude --chrome
   ```

> **Why two Claude instances?** The Windows instance keeps the Chrome Native Messaging Host
> (and its Named Pipe) alive. The Dev Container instance is where you do your actual work —
> it routes through the Named Pipe via the bridge to control Chrome.

## Commands

| Command      | Description                              |
|-------------|------------------------------------------|
| `make up`   | Build image and start interactive shell  |
| `make shell`| Open additional terminal in the container |

## Related

This project is a proof-of-concept solution for [anthropics/claude-code#15450](https://github.com/anthropics/claude-code/issues/15450) — a feature request for remote development support for the Chrome extension. The same approach can be adapted for Eclipse Che, GitHub Codespaces, Gitpod, or any environment that supports `host.docker.internal` or TCP port forwarding.

## Troubleshooting

- **"Extension not detected"** — Make sure the bridge is running on the host and Chrome has the Claude extension active.
- **Bridge container can't connect** — Verify the bridge is listening on port 9229. On Windows with WSL2, use `-BridgeHost '::'`.
- **Username mismatch** — The `USER` env var in the container must match the socket directory name. It defaults to `claude`.
- **"Pipe not found" (Windows)** — Make sure `claude --chrome` is running on Windows *before* starting `bridge-host.ps1`.
