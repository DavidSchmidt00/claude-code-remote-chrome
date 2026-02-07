#!/usr/bin/env node
"use strict";

const net = require("net");
const fs = require("fs");
const path = require("path");
const os = require("os");

const SOCK_DIR = `/tmp/claude-mcp-browser-bridge-${process.env.BRIDGE_USER || os.userInfo().username}`;
const TCP_PORT = parseInt(process.env.BRIDGE_PORT || "9229", 10);
const TCP_HOST = process.env.BRIDGE_HOST || "0.0.0.0";

function log(msg) {
  console.error(`[bridge-host] ${msg}`);
}

function findSock() {
  try {
    const files = fs.readdirSync(SOCK_DIR).filter((f) => f.endsWith(".sock"));
    if (files.length === 0) return null;
    files.sort();
    return path.join(SOCK_DIR, files[files.length - 1]);
  } catch {
    return null;
  }
}

const server = net.createServer((tcpConn) => {
  const addr = `${tcpConn.remoteAddress}:${tcpConn.remotePort}`;
  const sockPath = findSock();

  if (!sockPath) {
    log(`TCP client ${addr} connected but no NMH socket in ${SOCK_DIR}`);
    tcpConn.destroy();
    return;
  }

  log(`TCP client ${addr} -> NMH ${sockPath}`);

  const nmh = net.createConnection(sockPath, () => {
    log(`Connected to NMH socket`);
  });

  tcpConn.pipe(nmh);
  nmh.pipe(tcpConn);

  tcpConn.on("error", (e) => {
    log(`TCP error: ${e.message}`);
    nmh.destroy();
  });
  nmh.on("error", (e) => {
    log(`NMH error: ${e.message}`);
    tcpConn.destroy();
  });
  tcpConn.on("close", () => {
    log(`TCP client ${addr} disconnected`);
    nmh.destroy();
  });
  nmh.on("close", () => {
    log(`NMH disconnected`);
    tcpConn.destroy();
  });
});

server.listen(TCP_PORT, TCP_HOST, () => {
  log(`Listening on ${TCP_HOST}:${TCP_PORT}`);
  log(`NMH socket dir: ${SOCK_DIR}`);
  const sock = findSock();
  if (sock) log(`Found NMH socket: ${sock}`);
  else log(`No NMH socket yet, will check on each connection`);
});
