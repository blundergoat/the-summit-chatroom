#!/usr/bin/env pwsh
# GOAT System Uninstaller - Kilo CLI (PowerShell)
# Removes the Kilo CLI and its LM Studio configuration.
# Run this script in PowerShell on Windows, macOS, or Linux.

param()

$kiloPackage = if ($env:KILO_NPM_PACKAGE) { $env:KILO_NPM_PACKAGE } else { "kilo-cli" }
$kiloConfigDir = Join-Path (Join-Path $HOME ".kilocode") "cli"

function Test-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

Write-Host "Starting Kilo CLI uninstallation..." -ForegroundColor Cyan
Write-Host "npm package: $kiloPackage" -ForegroundColor Yellow

if (-not (Test-Command npm)) {
    Write-Host "npm is required to uninstall the Kilo CLI package." -ForegroundColor Red
    Write-Host "Install Node.js/npm or remove the package manually." -ForegroundColor Yellow
    exit 1
}

Write-Host "`nUninstalling Kilo CLI via npm" -ForegroundColor Cyan
npm uninstall -g $kiloPackage
if ($LASTEXITCODE -eq 0) {
    Write-Host "npm uninstall completed." -ForegroundColor Green
} else {
    Write-Host "npm uninstall reported an issue. Check with: npm list -g $kiloPackage" -ForegroundColor Yellow
}

Write-Host "`nCleaning Kilo CLI configuration" -ForegroundColor Cyan
if (Test-Path $kiloConfigDir) {
    $resp = Read-Host "Remove $kiloConfigDir and its contents? (y/n)"
    if ($resp -eq "y") {
        Remove-Item -Recurse -Force $kiloConfigDir
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Removed $kiloConfigDir" -ForegroundColor Green
        } else {
            Write-Host "Failed to remove $kiloConfigDir" -ForegroundColor Red
        }
    } else {
        Write-Host "Skipped removing $kiloConfigDir" -ForegroundColor Yellow
    }
} else {
    Write-Host "Config directory not found: $kiloConfigDir" -ForegroundColor Yellow
}

Write-Host "`nVerifying uninstall" -ForegroundColor Cyan
if (Test-Command kilo) {
    $kiloPath = (Get-Command kilo | Select-Object -ExpandProperty Source)
    Write-Host "kilo command still present at: $kiloPath" -ForegroundColor Yellow
    Write-Host "You may need to remove it from PATH or restart your shell." -ForegroundColor Yellow
} else {
    Write-Host "Kilo CLI command not found. Uninstall appears complete." -ForegroundColor Green
}

Write-Host "`nUninstallation process completed!" -ForegroundColor Green
