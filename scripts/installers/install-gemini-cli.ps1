#!/usr/bin/env pwsh
# GOAT System Installer - Gemini CLI (PowerShell)
# Run this script in PowerShell on Windows, macOS, or Linux.

function Test-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Ensure-NpmGlobalPath {
    $npmPrefix = (& npm prefix -g 2>$null)
    if (-not $npmPrefix) { return }
    $possibleBins = @(
        $npmPrefix,
        (Join-Path $npmPrefix "bin")
    )
    foreach ($binPath in $possibleBins) {
        if (-not ($env:PATH -split ';' | Where-Object { $_ -ieq $binPath })) {
            $env:PATH = "$binPath;$env:PATH"
            $currentUserPath = [Environment]::GetEnvironmentVariable("PATH", "User")
            if (-not ($currentUserPath -split ';' | Where-Object { $_ -ieq $binPath })) {
                [Environment]::SetEnvironmentVariable("PATH", "$currentUserPath;$binPath", "User")
            }
        }
    }
}

function Show-PathPrefixWarning {
    try { $prefix = npm config get prefix 2>$null } catch { $prefix = $null }
    $npmPaths = ($env:PATH -split ';' | Where-Object { $_ -match 'npm' }) | Sort-Object -Unique
    if ($npmPaths.Count -gt 1) {
        Write-Host "`nWarning: multiple npm-related paths detected in PATH. This can cause version drift between shells." -ForegroundColor Yellow
        foreach ($p in $npmPaths) { Write-Host " - $p" -ForegroundColor White }
        if ($prefix) { Write-Host "npm prefix: $prefix" -ForegroundColor White }
        Write-Host "Prefer a single global prefix (on Windows, %APPDATA%\npm) and remove extra npm/global bin paths." -ForegroundColor Yellow
    }
}

Write-Host "Starting Gemini CLI installation process..." -ForegroundColor Cyan
Write-Host "This will install Gemini CLI via npm package @google/gemini-cli" -ForegroundColor Yellow

Write-Host "`nChecking for Node.js installation..." -ForegroundColor Yellow
if (Test-Command node) {
    Write-Host "Node.js is already installed ($((node --version)))" -ForegroundColor Green
    if (-not (Test-Command npm)) {
        Write-Host "npm is not found. Please reinstall Node.js." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Node.js is required for Gemini CLI." -ForegroundColor Red
    $installNode = Read-Host "Would you like to install Node.js? (y/n)"
    if ($installNode -ne "y") {
        Write-Host "Node.js is required for Gemini CLI. Exiting." -ForegroundColor Red
        exit 1
    }

    if ($IsWindows) {
        Write-Host "Installing Node.js via winget..." -ForegroundColor Cyan
        winget install -e --id OpenJS.NodeJS.LTS
    } elseif ($IsLinux) {
        Write-Host "Installing Node.js for Linux..." -ForegroundColor Cyan
        bash -lc "curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - && sudo apt-get install -y nodejs"
    } elseif ($IsMacOS) {
        if (Test-Command brew) {
            Write-Host "Installing Node.js via Homebrew..." -ForegroundColor Cyan
            brew install node
        } else {
            Write-Host "Homebrew not found. Please install it first or use the Node.js installer." -ForegroundColor Yellow
            exit 1
        }
    }

    if (-not (Test-Command node)) {
        Write-Host "Node.js installation failed. Exiting." -ForegroundColor Red
        exit 1
    }
}

Ensure-NpmGlobalPath

Write-Host "`nInstalling Gemini CLI via npm..." -ForegroundColor Cyan
npm install -g @google/gemini-cli
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error installing Gemini CLI." -ForegroundColor Red
    Write-Host "Troubleshooting steps:" -ForegroundColor Yellow
    Write-Host "1) Check internet connection" -ForegroundColor White
    Write-Host "2) npm config list" -ForegroundColor White
    Write-Host "3) Try: npm install -g @google/gemini-cli" -ForegroundColor White
    exit 1
}

Write-Host "`nVerifying installation..." -ForegroundColor Yellow
if (Test-Command gemini) {
    Write-Host "Gemini CLI installed successfully!" -ForegroundColor Green
    gemini --version 2>$null
    Ensure-NpmGlobalPath
    Show-PathPrefixWarning

    Write-Host "`nNext steps:" -ForegroundColor Cyan
    Write-Host "1) Start the CLI: gemini" -ForegroundColor White
    Write-Host "2) Complete OAuth on first run" -ForegroundColor White
    Write-Host "3) Optional: set API key env var GEMINI_API_KEY" -ForegroundColor White
    Write-Host "4) Run 'gemini doctor' to verify setup" -ForegroundColor White
    Write-Host "5) Run 'gemini --help' for commands" -ForegroundColor White
} else {
    Write-Host "Gemini CLI installed but command not found in PATH. Restart your terminal or add the npm global bin to PATH (npm config get prefix)." -ForegroundColor Yellow
}

Write-Host "`nInstallation process completed!" -ForegroundColor Green
