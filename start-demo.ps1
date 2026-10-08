<#
.SYNOPSIS
    Starts the AgriEvidence demo: the LLM service (port 8100), the backend API (port 8000) and the
    frontend (port 5173), each in its own window, then opens the app in the browser.

.DESCRIPTION
    Close a service's window to stop it. Services whose port is already in use are skipped, so the
    script can be run again after closing one window. Ollama is optional: without it the assistant
    answers with the offline planner.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\start-demo.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\start-demo.ps1 -NoBrowser

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\start-demo.ps1 -Offline
    Frontend only (port 5174), with the sample trials kept in the browser: no Python or backend needed.
#>
param(
    # Don't open the browser when the app is up.
    [switch]$NoBrowser,
    # Only the frontend, in offline demo mode.
    [switch]$Offline
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

if ($Offline) {
    $offline = @{
        Name    = 'Offline demo'
        Folder  = 'Agricultural_Trial_Evidence_App_Frontend'
        Port    = 5174
        Command = 'npm run dev:offline -- --strictPort'
    }
}

$services = @(
    @{
        Name    = 'LLM service'
        Folder  = 'Agricultural_Trial_Evidence_App_LLM'
        Port    = 8100
        Needs   = '.venv\Scripts\python.exe'
        Setup   = 'python -m venv .venv; .venv\Scripts\pip install -r requirements.txt'
        Command = '.\.venv\Scripts\python.exe -m agritrial_llm'
    },
    @{
        Name    = 'Backend API'
        Folder  = 'Agricultural_Trial_Evidence_App_Backend'
        Port    = 8000
        Needs   = '.venv\Scripts\python.exe'
        Setup   = 'python -m venv .venv; .venv\Scripts\pip install -r requirements.txt'
        Command = '.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000'
    },
    @{
        Name    = 'Frontend'
        Folder  = 'Agricultural_Trial_Evidence_App_Frontend'
        Port    = 5173
        Needs   = 'node_modules'
        Setup   = 'npm install'
        Command = 'npm run dev -- --port 5173 --strictPort'
    }
)

function Test-PortInUse([int]$Port) {
    return [bool](Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
}

function Start-ServiceWindow($Service, [string]$Directory) {
    $title = "AgriEvidence $($Service.Name) (port $($Service.Port))"
    $quotedDirectory = $Directory.Replace("'", "''")
    $script = "`$Host.UI.RawUI.WindowTitle = '$title'; Set-Location -LiteralPath '$quotedDirectory'; $($Service.Command)"
    # An encoded command survives any characters in the path.
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
    Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoExit', '-NoProfile', '-EncodedCommand', $encoded
}

if ($Offline) {
    $directory = Join-Path $root $offline.Folder
    if (-not (Test-Path -LiteralPath (Join-Path $directory 'node_modules'))) {
        Write-Host 'The frontend is not set up. Run setup.cmd first (or npm install in the frontend folder).' -ForegroundColor Red
        exit 1
    }
    if (Test-PortInUse $offline.Port) {
        Write-Host "Offline demo: port $($offline.Port) is already in use, so it is probably running."
    } else {
        Start-ServiceWindow $offline $directory
        Write-Host "Offline demo: starting on port $($offline.Port)"
    }
    Write-Host ''
    Write-Host 'Offline demo: http://localhost:5174'
    Write-Host "Sign in with any email and password; emails starting with 'admin' get the admin role."
    Write-Host 'The six sample trials live in the browser; the assistant, imports and settings need the full app.'
    if (-not $NoBrowser) {
        $deadline = (Get-Date).AddSeconds(60)
        while ((Get-Date) -lt $deadline -and -not (Test-PortInUse $offline.Port)) { Start-Sleep -Seconds 1 }
        Start-Process 'http://localhost:5174'
    }
    exit 0
}

# Check the setup first, so nothing starts half-way.
$missing = $false
foreach ($service in $services) {
    $directory = Join-Path $root $service.Folder
    if (-not (Test-Path -LiteralPath (Join-Path $directory $service.Needs))) {
        Write-Host "$($service.Name) is not set up. Run setup.cmd first, or in $($service.Folder):" -ForegroundColor Red
        Write-Host "    $($service.Setup)"
        $missing = $true
    }
}
if ($missing) { exit 1 }

$frontendEnv = Join-Path $root 'Agricultural_Trial_Evidence_App_Frontend\.env'
if (-not (Test-Path -LiteralPath $frontendEnv)) {
    Copy-Item -LiteralPath "$frontendEnv.example" -Destination $frontendEnv
    Write-Host 'Created the frontend .env from .env.example (API at http://127.0.0.1:8000).'
}

# The model the LLM service uses by default: OLLAMA_MODEL in its .env, else qwen3.6.
$model = 'qwen3.6'
$llmEnv = Join-Path $root 'Agricultural_Trial_Evidence_App_LLM\.env'
if (Test-Path -LiteralPath $llmEnv) {
    $setting = Select-String -LiteralPath $llmEnv -Pattern '^\s*OLLAMA_MODEL\s*=\s*(\S+)' | Select-Object -First 1
    if ($setting) { $model = $setting.Matches[0].Groups[1].Value }
}
try {
    $tags = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 3
    $models = @($tags.models | ForEach-Object { $_.name })
    if ($models | Where-Object { $_ -eq $model -or $_ -eq "${model}:latest" }) {
        Write-Host "Ollama is running with $model." -ForegroundColor Green
    } else {
        Write-Host "Ollama is running but $model is not installed (ollama pull $model)." -ForegroundColor Yellow
        Write-Host 'The assistant will answer with the offline planner.' -ForegroundColor Yellow
    }
} catch {
    Write-Host 'Ollama is not running: the assistant will answer with the offline planner.' -ForegroundColor Yellow
}

foreach ($service in $services) {
    if (Test-PortInUse $service.Port) {
        Write-Host "$($service.Name): port $($service.Port) is already in use, so it is probably running. Skipped."
        continue
    }
    Start-ServiceWindow $service (Join-Path $root $service.Folder)
    Write-Host "$($service.Name): starting on port $($service.Port)"
}

Write-Host ''
Write-Host 'App:      http://localhost:5173'
Write-Host 'API docs: http://127.0.0.1:8000/docs'
Write-Host 'Sign in:  admin@agrievidence.demo / admin123  or  viewer@agrievidence.demo / viewer123'

if (-not $NoBrowser) {
    Write-Host 'Waiting for the backend and the frontend...'
    $deadline = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $deadline -and -not ((Test-PortInUse 8000) -and (Test-PortInUse 5173))) {
        Start-Sleep -Seconds 1
    }
    Start-Process 'http://localhost:5173'
}
