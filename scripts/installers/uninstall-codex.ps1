#!/usr/bin/env pwsh
# GOAT System Uninstaller - Codex CLI (PowerShell)
# Run this script in PowerShell on Windows, macOS, or Linux.

function Test-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

Write-Host "Uninstalling Codex CLI..." -ForegroundColor Cyan

Write-Host "`nChecking for Homebrew installation..." -ForegroundColor Cyan
if (Test-Command brew) {
    $null = brew list codex 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Found Codex installed via Homebrew" -ForegroundColor Yellow
        brew uninstall codex
        Write-Host "Homebrew uninstall completed" -ForegroundColor Green
    } else {
        Write-Host "Codex not found in Homebrew" -ForegroundColor Yellow
    }
} else {
    Write-Host "Homebrew not detected; skipping brew uninstall" -ForegroundColor Yellow
}

Write-Host "`nAttempting to uninstall all related npm packages..." -ForegroundColor Cyan
if (Test-Command npm) {
    Write-Host "Removing 'openai' package..."
    try { npm uninstall -g openai 2>$null } catch {}
    Write-Host "Removing '@openai/codex' package..."
    try { npm uninstall -g @openai/codex 2>$null } catch {}
    Write-Host "npm uninstall process completed." -ForegroundColor Green
} else {
    Write-Host "npm not found, skipping npm uninstall" -ForegroundColor Yellow
}

Write-Host "`nRemoving configuration and cache directories..." -ForegroundColor Cyan
$paths = @(
    (Join-Path $HOME ".openai"),
    (Join-Path $HOME ".config/codex"),
    (Join-Path $HOME ".codex")
)

foreach ($path in $paths) {
    if (Test-Path $path) {
        $resp = Read-Host "Remove $path ? This may affect other OpenAI tools. (y/n)"
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
if (Test-Command codex) {
    Write-Host "WARNING: Codex command still found at $(Get-Command codex | Select-Object -ExpandProperty Source)" -ForegroundColor Yellow
    Write-Host "You may need to remove it manually or restart your terminal." -ForegroundColor Yellow
} else {
    Write-Host "SUCCESS: Codex CLI has been uninstalled" -ForegroundColor Green
}

Write-Host "`nUninstall complete!" -ForegroundColor Green
