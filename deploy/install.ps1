#Requires -Version 5.1
<#
.SYNOPSIS
    Installs the e-automate AR MCP server for Claude Desktop.

.DESCRIPTION
    - Downloads the latest source from GitHub
    - Extracts to %LOCALAPPDATA%\Programs\eautomate-ar-mcp\
    - Verifies Python 3.10+ and installs pip dependencies
    - Prompts for SQL Server connection details
    - Writes the eautomate-ar entry into claude_desktop_config.json

.EXAMPLE
    # One-liner (recommended):
    irm https://raw.githubusercontent.com/Allied-Business-Solutions/eautomate-ar-mcp/main/deploy/install.ps1 | iex

    # Or run locally from a cloned repo:
    .\deploy\install.ps1
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$InstallDir       = Join-Path $env:LOCALAPPDATA 'Programs\eautomate-ar-mcp'
$ClaudeConfigPath = Join-Path $env:APPDATA 'Claude\claude_desktop_config.json'
$RepoOwner        = 'Allied-Business-Solutions'
$RepoName         = 'eautomate-ar-mcp'
$RepoZipUrl       = "https://github.com/$RepoOwner/$RepoName/archive/refs/heads/main.zip"

# ── Functions ─────────────────────────────────────────────────────────────────

function Get-PythonInfo {
    try {
        $output = & python --version 2>&1
        if ($LASTEXITCODE -eq 0 -and $output -match 'Python (\d+)\.(\d+)') {
            return @{ Path = (Get-Command python).Source; Major = [int]$Matches[1]; Minor = [int]$Matches[2] }
        }
    } catch { }
    return $null
}

function Install-RepoFiles {
    # Download into %LOCALAPPDATA% — avoids 8.3 short-path issues with %TEMP%
    $zipPath    = "$env:LOCALAPPDATA\eautomate-ar-mcp-download.zip"
    $stagingDir = "$env:LOCALAPPDATA\eautomate-ar-mcp-staging"
    Write-Host "  Downloading from GitHub..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $RepoZipUrl -OutFile $zipPath -UseBasicParsing
    Write-Host "  Extracting to $InstallDir..." -ForegroundColor Yellow
    if (Test-Path $stagingDir) { Remove-Item $stagingDir -Recurse -Force }
    New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
    Expand-Archive -Path $zipPath -DestinationPath $stagingDir -Force
    try { Remove-Item $zipPath -Force } catch { }   # cleanup — non-fatal
    # GitHub zip extracts to a subfolder like eautomate-ar-mcp-main\
    $extracted = Get-ChildItem $stagingDir -Directory | Select-Object -First 1
    if (Test-Path $InstallDir) { Remove-Item $InstallDir -Recurse -Force }
    Move-Item $extracted.FullName $InstallDir
    try { Remove-Item $stagingDir -Recurse -Force } catch { }  # cleanup — non-fatal
}

function Read-WithDefault {
    param([string]$Prompt, [string]$Default)
    $display = if ($Default) { "$Prompt [$Default]" } else { $Prompt }
    $value = Read-Host $display
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    return $value.Trim()
}

function Read-Masked {
    param([string]$Prompt)
    $secure = Read-Host $Prompt -AsSecureString
    return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
}

function Merge-ClaudeConfig {
    param([string]$ConfigPath, [PSCustomObject]$McpEntry)
    if (Test-Path $ConfigPath) {
        $json = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    } else {
        New-Item -ItemType Directory -Path (Split-Path $ConfigPath) -Force | Out-Null
        $json = [PSCustomObject]@{}
    }
    if (-not $json.PSObject.Properties['mcpServers']) {
        $json | Add-Member -MemberType NoteProperty -Name 'mcpServers' -Value ([PSCustomObject]@{})
    }
    $json.mcpServers | Add-Member -MemberType NoteProperty -Name 'eautomate-ar' -Value $McpEntry -Force
    [System.IO.File]::WriteAllText(
        $ConfigPath,
        ($json | ConvertTo-Json -Depth 10),
        [System.Text.UTF8Encoding]::new($false)
    )
}

# ── Main ──────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "e-automate AR MCP Installer" -ForegroundColor Cyan
Write-Host "============================" -ForegroundColor Cyan
Write-Host ""

# 1. Python
Write-Host "Checking Python..." -ForegroundColor Cyan
$py = Get-PythonInfo
if (-not $py) {
    Write-Host "  ERROR: Python not found. Install Python 3.10+ from https://python.org and re-run." -ForegroundColor Red
    exit 1
}
if ($py.Major -lt 3 -or ($py.Major -eq 3 -and $py.Minor -lt 10)) {
    Write-Host "  ERROR: Python $($py.Major).$($py.Minor) found but 3.10+ is required." -ForegroundColor Red
    exit 1
}
Write-Host "  Python $($py.Major).$($py.Minor) found at $($py.Path)" -ForegroundColor Green

# 2. Download + extract
Write-Host ""
Write-Host "Downloading e-automate AR MCP..." -ForegroundColor Cyan
Install-RepoFiles
Write-Host "  Files installed to $InstallDir" -ForegroundColor Green

# 3. Install Python dependencies
Write-Host ""
Write-Host "Installing Python dependencies..." -ForegroundColor Cyan
$reqFile = Join-Path $InstallDir "requirements.txt"
& python -m pip install -r $reqFile --quiet
Write-Host "  Dependencies installed." -ForegroundColor Green

# 4. Collect connection details
Write-Host ""
Write-Host "SQL Server Connection" -ForegroundColor Cyan
Write-Host "---------------------"
Write-Host "The MCP server connects to your e-automate database read-only."
Write-Host "For SQL login, create a read-only account with db_datareader on the e-automate DB."
Write-Host "Leave username blank to use Windows Authentication instead."
Write-Host ""

$eaServer   = Read-WithDefault "SQL Server hostname"   "your-sql-server"
$eaDatabase = Read-WithDefault "Database name"         "your-eautomate-db"
$eaUsername = Read-WithDefault "SQL login username (blank = Windows Auth)" ""
$eaPassword = ""
if ($eaUsername) {
    $eaPassword = Read-Masked "SQL login password"
}

# 5. Write .env
$envFile = Join-Path $InstallDir ".env"
$envContent = @"
EA_SERVER=$eaServer
EA_DATABASE=$eaDatabase
EA_USERNAME=$eaUsername
EA_PASSWORD=$eaPassword
"@
[System.IO.File]::WriteAllText($envFile, $envContent, [System.Text.UTF8Encoding]::new($false))
Write-Host ""
$authMode = if ($eaUsername) { "SQL login ($eaUsername)" } else { "Windows Authentication" }
Write-Host "  .env written — Server=$eaServer, DB=$eaDatabase, Auth=$authMode" -ForegroundColor Green

# 6. Write claude_desktop_config.json
Write-Host ""
Write-Host "Registering with Claude Desktop..." -ForegroundColor Cyan

$mcpEnv = [PSCustomObject]@{
    EA_SERVER   = $eaServer
    EA_DATABASE = $eaDatabase
}
if ($eaUsername) {
    $mcpEnv | Add-Member -MemberType NoteProperty -Name 'EA_USERNAME' -Value $eaUsername
    $mcpEnv | Add-Member -MemberType NoteProperty -Name 'EA_PASSWORD' -Value $eaPassword
}

$mcpEntry = [PSCustomObject]@{
    command = $py.Path
    args    = @((Join-Path $InstallDir "server.py"))
    env     = $mcpEnv
}

Merge-ClaudeConfig -ConfigPath $ClaudeConfigPath -McpEntry $mcpEntry
Write-Host "  $ClaudeConfigPath updated" -ForegroundColor Green

# 7. Done
Write-Host ""
Write-Host "Installation complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Restart Claude Desktop"
Write-Host "  2. Ask Claude: 'Search for customer Acme' to verify the connection"
Write-Host "  3. If you see a connection error, check .env at:"
Write-Host "       $envFile"
Write-Host ""
