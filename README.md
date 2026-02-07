# Chrome Bridge for Claude Code in Docker

Run Claude Code inside a Docker container while controlling Chrome on your host machine.

## What it does

Claude Code has a "Claude in Chrome" feature that lets it control your browser — navigate pages, fill forms, take screenshots, etc. Normally this only works when Claude Code runs directly on your machine. This project bridges that gap so Claude Code running in a container can talk to Chrome on your host.

## How it works

Two small Node.js scripts forward messages between the container and your host:

```
Container                          Host
Claude Code                        Chrome
    |                                |
    v                                ^
bridge-container.js  --TCP:9229-->  bridge-host.js
(Unix socket)                      (Unix socket)
```

## Prerequisites

- Docker (Docker Desktop, OrbStack, or similar)
- Node.js on the host (for bridge-host.js)
- Chrome with the [Claude browser extension](https://claude.ai/chrome) installed
- Claude account credentials

## Setup

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

4. **Inside the container**, start the container bridge and Claude:

   ```bash
   node ~/bridge-container.js &
   claude --chrome
   ```

5. Ask Claude to do something in Chrome, e.g. `open google.com`.

## Commands

| Command      | Description                              |
|-------------|------------------------------------------|
| `make up`   | Build image and start interactive shell  |
| `make shell`| Open additional terminal in the container |

## Related

This project is a proof-of-concept solution for [anthropics/claude-code#15450](https://github.com/anthropics/claude-code/issues/15450) — a feature request for remote development support for the Chrome extension. The same approach can be adapted for Eclipse Che, GitHub Codespaces, Gitpod, or any environment that supports `host.docker.internal` or TCP port forwarding.

## Troubleshooting

- **"Extension not detected"** — Make sure `bridge-host.js` is running on the host and Chrome has the Claude extension active.
- **Bridge container can't connect** — Verify `bridge-host.js` is listening on port 9229.
- **Username mismatch** — The `USER` env var in the container must match the socket directory name. It defaults to `claude`.
