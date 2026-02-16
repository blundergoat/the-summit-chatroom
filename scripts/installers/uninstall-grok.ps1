#!/usr/bin/env pwsh
# GOAT System Uninstaller - Grok CLI (PowerShell)
# Run this script in PowerShell on Windows, macOS, or Linux.

function Test-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

$grokRoot = Join-Path $HOME ".grok"
$grokSettings = Join-Path $grokRoot "user-settings.json"

Write-Host "Starting Grok CLI uninstallation process..." -ForegroundColor Cyan

if (-not (Test-Command npm)) {
    Write-Host "npm is not found. Uninstallation requires npm." -ForegroundColor Red
    exit 1
}

Write-Host "`nUninstalling Grok CLI via npm" -ForegroundColor Cyan
npm uninstall -g @vibe-kit/grok-cli
if ($LASTEXITCODE -eq 0) {
    Write-Host "Grok CLI uninstalled successfully!" -ForegroundColor Green
} else {
    Write-Host "Error uninstalling Grok CLI. It might not be installed globally. Check with 'npm list -g @vibe-kit/grok-cli'." -ForegroundColor Yellow
}

Write-Host "`nCleaning up Grok CLI user settings" -ForegroundColor Cyan
if (Test-Path $grokRoot) {
    $resp = Read-Host "Remove $grokRoot and all its contents? (y/n)"
    if ($resp -eq "y") {
        Remove-Item $grokRoot -Recurse -Force
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Removed $grokRoot" -ForegroundColor Green
        } else {
            Write-Host "Failed to remove $grokRoot" -ForegroundColor Red
        }
    } else {
        Write-Host "Skipped removal of $grokRoot" -ForegroundColor Yellow
    }
}

Write-Host "`nUninstallation process completed!" -ForegroundColor Green
