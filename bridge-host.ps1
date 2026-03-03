#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    TCP-to-Named Pipe bridge for Claude Code Chrome extension on Windows.
    Drop-in replacement for bridge-host.js — no Node.js required.

.DESCRIPTION
    Listens on TCP port 9229 and forwards each connection to the Claude browser
    extension's Named Pipe (\\.\pipe\claude-mcp-browser-bridge-<user>), enabling
    Claude Code running inside a devcontainer to control Chrome on the host machine.

    On Windows, Claude Code uses a Named Pipe instead of a Unix socket.

.PARAMETER BridgeUser
    Username whose named pipe to connect to. Defaults to BRIDGE_USER env var,
    then the current Windows user ($env:USERNAME).

.PARAMETER BridgePort
    TCP port to listen on. Defaults to BRIDGE_PORT env var, then 9229.

.PARAMETER BridgeHost
    IP address to bind to. Defaults to BRIDGE_HOST env var, then 0.0.0.0.

.EXAMPLE
    .\bridge-host.ps1

.EXAMPLE
    .\bridge-host.ps1 -BridgeHost '::'
#>

param(
    [string] $BridgeUser = ($env:BRIDGE_USER ?? $env:USERNAME),
    [int]    $BridgePort = [int]($env:BRIDGE_PORT ?? '9229'),
    [string] $BridgeHost = ($env:BRIDGE_HOST ?? '0.0.0.0')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$PipeName = "claude-mcp-browser-bridge-$BridgeUser"

function Write-Log([string]$Msg) {
    $ts = (Get-Date).ToString('HH:mm:ss')
    Write-Host "[$ts bridge-host] $Msg"
}

function Test-Pipe([string]$Name) {
    try {
        $pipes = [System.IO.Directory]::GetFiles('\\.\pipe\')
        return ($pipes | Where-Object { $_ -like "*$Name*" }).Count -gt 0
    } catch { return $false }
}

# ── Per-connection handler ────────────────────────────────────────────────────
# Runs in its own runspace so the TCP accept loop is never blocked.
$connectionHandler = {
    param(
        [System.Net.Sockets.TcpClient] $TcpClient,
        [string]                       $Addr,
        [string]                       $PipeName
    )

    function Log([string]$Msg) { Write-Host "[bridge-host] $Msg" }

    Log "TCP client $Addr -> Named Pipe \\.\pipe\$PipeName"

    $pipeStream = [System.IO.Pipes.NamedPipeClientStream]::new(
        '.',
        $PipeName,
        [System.IO.Pipes.PipeDirection]::InOut,
        [System.IO.Pipes.PipeOptions]::Asynchronous
    )

    try {
        $pipeStream.Connect(5000)   # 5-second timeout
        Log "Connected to Named Pipe"
    } catch {
        Log "Named Pipe connect error: $_"
        $TcpClient.Close()
        $pipeStream.Dispose()
        return
    }

    $tcpStream = $TcpClient.GetStream()

    try {
        # Pipe both directions concurrently
        $toTcp  = $pipeStream.CopyToAsync($tcpStream)
        $toPipe = $tcpStream.CopyToAsync($pipeStream)

        # Wait until either side closes
        [void][System.Threading.Tasks.Task]::WaitAny($toTcp, $toPipe)
    } catch {
        # Expected when either side disconnects
    } finally {
        Log "TCP client $Addr disconnected"
        try { $tcpStream.Close()  } catch { }
        try { $pipeStream.Close() } catch { }
        try { $TcpClient.Close()  } catch { }
    }
}

# ── Main ─────────────────────────────────────────────────────────────────────

$listener = [System.Net.Sockets.TcpListener]::new(
    [System.Net.IPAddress]::Parse($BridgeHost),
    $BridgePort
)
$listener.Start()

Write-Log "Listening on ${BridgeHost}:${BridgePort}"
Write-Log "Named Pipe: \\.\pipe\$PipeName"
if (Test-Pipe $PipeName) { Write-Log "Pipe found -- ready" }
else                     { Write-Log "Pipe not found yet -- will connect on each incoming connection" }

# RunspacePool lets each connection run in its own PowerShell thread
$pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, 8)
$pool.Open()

Write-Log "Press Ctrl+C to stop."

try {
    while ($true) {
        # Poll instead of blocking so Ctrl+C can interrupt cleanly
        while (-not $listener.Pending()) { Start-Sleep -Milliseconds 100 }
        $tcpClient = $listener.AcceptTcpClient()
        $addr      = "$($tcpClient.Client.RemoteEndPoint)"

        $ps = [System.Management.Automation.PowerShell]::Create()
        $ps.RunspacePool = $pool
        [void]$ps.AddScript($connectionHandler)
                  .AddArgument($tcpClient)
                  .AddArgument($addr)
                  .AddArgument($PipeName)
        [void]$ps.BeginInvoke()
    }
} finally {
    $listener.Stop()
    $pool.Close()
    Write-Log "Stopped."
}
