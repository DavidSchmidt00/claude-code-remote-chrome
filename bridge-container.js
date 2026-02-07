#!/usr/bin/env node
"use strict";

const net = require("net");
const fs = require("fs");
const path = require("path");

const SOCK_DIR = `/tmp/claude-mcp-browser-bridge-${process.env.USER || require("os").userInfo().username}`;
const TCP_HOST = process.env.BRIDGE_TCP_HOST || "host.docker.internal";
const TCP_PORT = parseInt(process.env.BRIDGE_PORT || "9229", 10);

const sockPath = path.join(SOCK_DIR, `${process.pid}.sock`);

function log(msg) {
  console.error(`[bridge-container] ${msg}`);
}

function logData(label, data) {
  if (data.length >= 4) {
    const len = data.readUInt32LE(0);
    const json = data.slice(4, 4 + len).toString();
    log(`[${label}] len=${len} data=${json.substring(0, 500)}`);
  } else {
    log(`[${label}] raw=${data.toString("hex")}`);
  }
}

function cleanup() {
  try { fs.unlinkSync(sockPath); } catch {}
  try { fs.rmdirSync(SOCK_DIR); } catch {}
}

process.on("SIGINT", () => { cleanup(); process.exit(0); });
process.on("SIGTERM", () => { cleanup(); process.exit(0); });
process.on("exit", cleanup);

fs.mkdirSync(SOCK_DIR, { recursive: true, mode: 0o700 });
try { fs.unlinkSync(sockPath); } catch {}

const server = net.createServer((mcpConn) => {
  log(`MCP connected`);

  const tcp = net.createConnection({ host: TCP_HOST, port: TCP_PORT }, () => {
    log(`Connected to host bridge`);
  });

  mcpConn.on("data", (data) => {
    logData("MCP->NMH", data);
    tcp.write(data);
  });
  tcp.on("data", (data) => {
    logData("NMH->MCP", data);
    mcpConn.write(data);
  });

  mcpConn.on("error", (e) => log(`MCP error: ${e.message}`));
  tcp.on("error", (e) => log(`TCP error: ${e.message}`));
  mcpConn.on("close", () => { log(`MCP disconnected`); tcp.destroy(); });
  tcp.on("close", () => { log(`TCP disconnected`); mcpConn.destroy(); });
});

server.listen(sockPath, () => {
  fs.chmodSync(sockPath, 0o600);
  log(`Listening on ${sockPath}`);
  log(`Forwarding to ${TCP_HOST}:${TCP_PORT}`);
});
