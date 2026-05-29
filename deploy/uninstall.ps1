<#
.SYNOPSIS
    Removes the eautomate-ar MCP server registration from Claude config files.

.DESCRIPTION
    Removes the "eautomate-ar" entry from Claude Desktop and/or Claude Code config.
    Does not uninstall Python packages or delete any files.

.PARAMETER Target
    "ClaudeDesktop" (default) — %APPDATA%\Claude\claude_desktop_config.json
    "ClaudeCode"              — %USERPROFILE%\.claude\settings.json
    "Both"                    — removes from both
#>

param(
    [ValidateSet("ClaudeDesktop","ClaudeCode","Both")]
    [string]$Target = "ClaudeDesktop"
)

$ErrorActionPreference = "Stop"

Write-Host "`ne-automate MCP Server — Uninstaller" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

function Remove-MCP {
    param([string]$ConfigFile, [string]$Label)

    if (-not (Test-Path $ConfigFile)) {
        Write-Host "  $Label : config file not found — skipping." -ForegroundColor Yellow
        return
    }

    $config = Get-Content $ConfigFile -Raw | ConvertFrom-Json

    if ($config.mcpServers -and ($config.mcpServers | Get-Member -Name "eautomate-ar" -MemberType NoteProperty)) {
        $config.mcpServers.PSObject.Properties.Remove("eautomate-ar")
        $config | ConvertTo-Json -Depth 10 | Set-Content $ConfigFile -Encoding utf8
        Write-Host "  $Label : removed 'eautomate-ar' from $ConfigFile" -ForegroundColor Green
    } else {
        Write-Host "  $Label : 'eautomate-ar' was not registered — nothing to remove." -ForegroundColor Yellow
    }
}

$desktopConfig = Join-Path $env:APPDATA "Claude\claude_desktop_config.json"
$codeConfig    = Join-Path $env:USERPROFILE ".claude\settings.json"

if ($Target -eq "ClaudeDesktop" -or $Target -eq "Both") {
    Remove-MCP -ConfigFile $desktopConfig -Label "Claude Desktop"
}
if ($Target -eq "ClaudeCode" -or $Target -eq "Both") {
    Remove-MCP -ConfigFile $codeConfig -Label "Claude Code"
}

Write-Host "`nRestart Claude Desktop / Claude Code to apply the change." -ForegroundColor Cyan
Write-Host ""
