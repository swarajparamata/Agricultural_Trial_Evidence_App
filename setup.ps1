<#
.SYNOPSIS
    One-time setup on Windows: a Python virtual environment for the LLM service and for the backend, and the
    frontend's npm packages. Safe to run again.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\setup.ps1
#>

$root = $PSScriptRoot
$llm = Join-Path $root 'Agricultural_Trial_Evidence_App_LLM'
$backend = Join-Path $root 'Agricultural_Trial_Evidence_App_Backend'
$frontend = Join-Path $root 'Agricultural_Trial_Evidence_App_Frontend'

function Stop-Setup([string]$message) {
    Write-Host $message -ForegroundColor Red
    exit 1
}

function Assert-Success([string]$what) {
    if ($LASTEXITCODE -ne 0) { Stop-Setup "$what failed (exit code $LASTEXITCODE)." }
}

foreach ($dir in $llm, $backend, $frontend) {
    if (-not (Test-Path -LiteralPath (Join-Path $dir 'README.md'))) {
        Stop-Setup "$(Split-Path $dir -Leaf) is missing. Clone with --recursive, or run: git submodule update --init"
    }
}

# Python 3.10 or newer, preferring 3.12 and 3.11, found through the py launcher or on the PATH.
$python = $null
if (Get-Command py -ErrorAction SilentlyContinue) {
    $installed = @{}
    foreach ($line in (& py -0p 2>$null)) {
        if ($line -match '-V?:?(3\.\d+)\S*\s+\*?\s*(\S.*\.exe)\s*$') { $installed[$Matches[1]] = $Matches[2].Trim() }
    }
    foreach ($version in '3.12', '3.11', '3.13', '3.10') {
        if ($installed.ContainsKey($version)) { $python = $installed[$version]; break }
    }
}
if (-not $python) {
    $command = Get-Command python -ErrorAction SilentlyContinue
    if ($command) { $python = $command.Source }
}
if ($python) {
    & $python -c "import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)"
    if ($LASTEXITCODE -ne 0) { $python = $null }
}
if (-not $python) { Stop-Setup 'Python 3.10 or newer is required: https://www.python.org/downloads/' }
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { Stop-Setup 'Node.js 20 or newer is required: https://nodejs.org/' }
& node -e "process.exit(Number(process.versions.node.split('.')[0]) >= 20 ? 0 : 1)"
if ($LASTEXITCODE -ne 0) { Stop-Setup "Node.js 20 or newer is required (found $(node --version))." }

foreach ($dir in $llm, $backend) {
    Write-Host "`n$(Split-Path $dir -Leaf): Python packages ($(& $python --version))" -ForegroundColor Cyan
    $venvPython = Join-Path $dir '.venv\Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $venvPython)) {
        & $python -m venv (Join-Path $dir '.venv')
        Assert-Success 'Creating the virtual environment'
    }
    & $venvPython -m pip install --quiet --disable-pip-version-check -r (Join-Path $dir 'requirements.txt')
    Assert-Success 'Installing the Python packages'
}

Write-Host "`n$(Split-Path $frontend -Leaf): npm packages" -ForegroundColor Cyan
Push-Location -LiteralPath $frontend
if (Test-Path -LiteralPath 'node_modules') { & npm install --no-audit --no-fund } else { & npm ci --no-audit --no-fund }
$npmExit = $LASTEXITCODE
Pop-Location
if ($npmExit -ne 0) { Stop-Setup "Installing the npm packages failed (exit code $npmExit)." }
$frontendEnv = Join-Path $frontend '.env'
if (-not (Test-Path -LiteralPath $frontendEnv)) { Copy-Item -LiteralPath "$frontendEnv.example" -Destination $frontendEnv }

Write-Host "`nSetup complete." -ForegroundColor Green
Write-Host '  Full app:           start-demo.cmd   (or: powershell -ExecutionPolicy Bypass -File .\start-demo.ps1)'
Write-Host '  Offline demo only:  start-demo.cmd -Offline'
try {
    Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 2 | Out-Null
} catch {
    Write-Host ''
    Write-Host 'Optional, for answers from a real LLM: install Ollama (https://ollama.com/download) and pull a model,'
    Write-Host "e.g. 'ollama pull qwen3:4b', then set it in Settings -> AI assistant. Without it the assistant uses"
    Write-Host 'its offline planner.'
}
