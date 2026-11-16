# Starts the Voice Studio backend on this computer.
#   .\run_server.ps1            -> http://127.0.0.1:8765 (only this PC)
#   .\run_server.ps1 -Lan       -> listens on the local network (for Android); enable VS_REQUIRE_AUTH_FOR_AI
param([switch]$Lan, [int]$Port = 8765)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
if (-not (Test-Path .venv)) {
    py -3.12 -m venv .venv
    .\.venv\Scripts\python.exe -m pip install --upgrade pip
    .\.venv\Scripts\python.exe -m pip install -r requirements-ai.txt
}
$hostAddr = if ($Lan) { '0.0.0.0' } else { '127.0.0.1' }
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host $hostAddr --port $Port
