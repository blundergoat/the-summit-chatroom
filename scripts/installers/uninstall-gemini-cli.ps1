#!/usr/bin/env pwsh
# GOAT System Uninstaller - Gemini CLI (PowerShell)
# Run this script in PowerShell on Windows, macOS, or Linux.

function Test-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

Write-Host "Starting Gemini CLI uninstallation process..." -ForegroundColor Cyan

if (-not (Test-Command npm)) {
    Write-Host "npm is required to uninstall the Gemini CLI package." -ForegroundColor Red
    Write-Host "Please install Node.js/npm or remove the package manually." -ForegroundColor Yellow
    exit 1
}

Write-Host "`nUninstalling Gemini CLI via npm" -ForegroundColor Cyan
npm uninstall -g @google/gemini-cli
if ($LASTEXITCODE -eq 0) {
    Write-Host "Gemini CLI uninstalled via npm." -ForegroundColor Green
} else {
    Write-Host "npm uninstall reported an issue. The package may not have been installed globally. You can check with: npm list -g @google/gemini-cli" -ForegroundColor Yellow
}

Write-Host "`nCleaning up Gemini CLI data" -ForegroundColor Cyan
$possibleDirs = @(
    (Join-Path $HOME ".config/gemini"),
    (Join-Path $HOME ".config/google-gemini"),
    (Join-Path $HOME ".cache/gemini")
)

foreach ($dir in $possibleDirs) {
    if (Test-Path $dir) {
        $resp = Read-Host "Remove $dir ? (y/n)"
        if ($resp -eq "y") {
            Remove-Item -Recurse -Force $dir
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Removed: $dir" -ForegroundColor Green
            } else {
                Write-Host "Failed to remove: $dir" -ForegroundColor Red
            }
        } else {
            Write-Host "Skipped: $dir" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Not found: $dir" -ForegroundColor Yellow
    }
}

Write-Host "`nVerifying uninstall" -ForegroundColor Cyan
if (Test-Command gemini) {
    $geminiPath = (Get-Command gemini | Select-Object -ExpandProperty Source)
    Write-Host "gemini command still present at: $geminiPath" -ForegroundColor Yellow
    Write-Host "You may need to remove it from PATH or restart your shell." -ForegroundColor Yellow
} else {
    Write-Host "Gemini CLI command not found. Uninstall appears complete." -ForegroundColor Green
}

Write-Host "`nUninstallation process completed!" -ForegroundColor Green
