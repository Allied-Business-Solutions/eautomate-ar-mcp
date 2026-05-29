<#
.SYNOPSIS
    Installs the e-automate MCP server and registers it with Claude.

.DESCRIPTION
    - Verifies Python 3.10+ is available
    - Installs Python dependencies (mcp, pyodbc, python-dotenv)
    - Copies .env.example to .env if .env does not exist
    - Registers the MCP server in the Claude config file.
      Claude Desktop : %APPDATA%\Claude\claude_desktop_config.json
      Claude Code    : %USERPROFILE%\.claude\settings.json  (use -Target ClaudeCode)

.PARAMETER ServerPath
    Full path to the cloned eautomate-mcp directory.
    Defaults to the parent of this script's directory.

.PARAMETER EAServer
    SQL Server hostname for e-automate. Default: absapp4

.PARAMETER EADatabase
    e-automate database name. Default: CoAlliedBusiness

.PARAMETER EAUsername
    SQL Server login username. Leave blank to use Windows Authentication.

.PARAMETER EAPassword
    SQL Server login password. Required when EAUsername is set.

.PARAMETER Target
    Which Claude product to register with.
    "ClaudeDesktop" (default) — %APPDATA%\Claude\claude_desktop_config.json
    "ClaudeCode"              — %USERPROFILE%\.claude\settings.json
    "Both"                    — registers in both config files

.EXAMPLE
    .\install.ps1
    .\install.ps1 -EAUsername earead -EAPassword "s3cr3t"
    .\install.ps1 -Target ClaudeCode
    .\install.ps1 -EAServer myserver -EADatabase MyDatabase -Target Both
#>

param(
    [string]$ServerPath = (Split-Path $PSScriptRoot -Parent),
    [string]$EAServer   = "absapp4",
    [string]$EADatabase = "CoAlliedBusiness",
    [string]$EAUsername = "",
    [string]$EAPassword = "",
    [ValidateSet("ClaudeDesktop","ClaudeCode","Both")]
    [string]$Target     = "ClaudeDesktop"
)

$ErrorActionPreference = "Stop"

Write-Host "`ne-automate MCP Server — Installer" -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan

# ── 1. Verify Python ────────────────────────────────────────────────────────
Write-Host "`n[1/4] Checking Python..." -ForegroundColor Yellow
try {
    $pyVersion = python --version 2>&1
    Write-Host "      Found: $pyVersion" -ForegroundColor Green
    $major, $minor = ($pyVersion -replace "Python ","").Split(".")[0,1]
    if ([int]$major -lt 3 -or ([int]$major -eq 3 -and [int]$minor -lt 10)) {
        throw "Python 3.10 or higher is required."
    }
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
    Write-Host "Please install Python 3.10+ from https://python.org and re-run." -ForegroundColor Red
    exit 1
}

# ── 2. Install dependencies ──────────────────────────────────────────────────
Write-Host "`n[2/4] Installing Python dependencies..." -ForegroundColor Yellow
$reqFile = Join-Path $ServerPath "requirements.txt"
python -m pip install -r $reqFile --quiet
Write-Host "      Dependencies installed." -ForegroundColor Green

# ── 3. Create .env ───────────────────────────────────────────────────────────
Write-Host "`n[3/4] Configuring .env..." -ForegroundColor Yellow
$envFile    = Join-Path $ServerPath ".env"
$envExample = Join-Path $ServerPath ".env.example"

if (-not (Test-Path $envFile)) {
    Copy-Item $envExample $envFile
    (Get-Content $envFile) `
        -replace "EA_SERVER=.*",   "EA_SERVER=$EAServer" `
        -replace "EA_DATABASE=.*", "EA_DATABASE=$EADatabase" `
        -replace "EA_USERNAME=.*", "EA_USERNAME=$EAUsername" `
        -replace "EA_PASSWORD=.*", "EA_PASSWORD=$EAPassword" |
        Set-Content $envFile -Encoding utf8
    $authMode = if ($EAUsername) { "SQL login ($EAUsername)" } else { "Windows Authentication" }
    Write-Host "      Created .env — Server=$EAServer, DB=$EADatabase, Auth=$authMode" -ForegroundColor Green
} else {
    Write-Host "      .env already exists — skipping (edit it manually if needed)." -ForegroundColor Yellow
}

# ── 4. Build MCP entry ───────────────────────────────────────────────────────
$serverScript = Join-Path $ServerPath "server.py"
$pythonPath   = (Get-Command python).Source

$mcpEnv = [PSCustomObject]@{
    EA_SERVER   = $EAServer
    EA_DATABASE = $EADatabase
}
if ($EAUsername) {
    $mcpEnv | Add-Member -MemberType NoteProperty -Name "EA_USERNAME" -Value $EAUsername
    $mcpEnv | Add-Member -MemberType NoteProperty -Name "EA_PASSWORD" -Value $EAPassword
}

$mcpEntry = [PSCustomObject]@{
    command = $pythonPath
    args    = @($serverScript)
    env     = $mcpEnv
}

function Register-MCP {
    param([string]$ConfigFile, [string]$Label)

    $dir = Split-Path $ConfigFile -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force $dir | Out-Null
    }

    if (Test-Path $ConfigFile) {
        $config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
    } else {
        $config = [PSCustomObject]@{}
    }

    if (-not ($config | Get-Member -Name "mcpServers" -MemberType NoteProperty)) {
        $config | Add-Member -MemberType NoteProperty -Name "mcpServers" -Value ([PSCustomObject]@{})
    }

    $config.mcpServers | Add-Member -MemberType NoteProperty -Name "eautomate-ar" -Value $mcpEntry -Force
    $config | ConvertTo-Json -Depth 10 | Set-Content $ConfigFile -Encoding utf8
    Write-Host "      Registered in $Label" -ForegroundColor Green
    Write-Host "      -> $ConfigFile" -ForegroundColor DarkGray
}

Write-Host "`n[4/4] Registering MCP server with Claude..." -ForegroundColor Yellow

$desktopConfig = Join-Path $env:APPDATA "Claude\claude_desktop_config.json"
$codeConfig    = Join-Path $env:USERPROFILE ".claude\settings.json"

if ($Target -eq "ClaudeDesktop" -or $Target -eq "Both") {
    Register-MCP -ConfigFile $desktopConfig -Label "Claude Desktop"
}
if ($Target -eq "ClaudeCode" -or $Target -eq "Both") {
    Register-MCP -ConfigFile $codeConfig -Label "Claude Code"
}

Write-Host "`nInstallation complete!" -ForegroundColor Cyan
Write-Host "Restart Claude Desktop / Claude Code to load the new MCP server." -ForegroundColor Cyan
Write-Host ""
