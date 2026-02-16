#!/usr/bin/env pwsh
# GOAT System Uninstaller - GitHub Copilot CLI (PowerShell)
# Run this script in PowerShell on Windows, macOS, or Linux.

function Test-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

Write-Host "Uninstalling GitHub Copilot CLI..." -ForegroundColor Cyan

Write-Host "`nAttempting to uninstall via npm..." -ForegroundColor Cyan
if (Test-Command npm) {
    npm uninstall -g @github/copilot
    if ($LASTEXITCODE -eq 0) {
        Write-Host "GitHub Copilot CLI uninstalled via npm." -ForegroundColor Green
    } else {
        Write-Host "npm uninstall reported an issue. The package may not have been installed globally." -ForegroundColor Yellow
        Write-Host "You can check with: npm list -g @github/copilot" -ForegroundColor Yellow
    }
} else {
    Write-Host "npm not found. Please install Node.js/npm or remove the global package manually." -ForegroundColor Red
}

Write-Host "`nRemoving configuration and cache directories..." -ForegroundColor Cyan
$paths = @(
    (Join-Path $HOME ".copilot"),
    (Join-Path $HOME ".config/copilot"),
    (Join-Path $HOME ".config/github-copilot"),
    (Join-Path $HOME ".cache/copilot")
)

foreach ($path in $paths) {
    if (Test-Path $path) {
        $resp = Read-Host "Remove $path ? (y/n)"
        if ($resp -eq "y") {
            Remove-Item -Recurse -Force $path
            Write-Host "Removed: $path" -ForegroundColor Green
        } else {
            Write-Host "Skipped: $path" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Directory not found: $path" -ForegroundColor Yellow
    }
}

Write-Host "`nVerifying uninstall..." -ForegroundColor Cyan
if (Test-Command copilot) {
    Write-Host "WARNING: copilot command still found at $(Get-Command copilot | Select-Object -ExpandProperty Source)" -ForegroundColor Yellow
    Write-Host "You may need to remove it manually or restart your terminal." -ForegroundColor Yellow
} else {
    Write-Host "SUCCESS: GitHub Copilot CLI has been uninstalled" -ForegroundColor Green
}

Write-Host "`nUninstall complete!" -ForegroundColor Green
