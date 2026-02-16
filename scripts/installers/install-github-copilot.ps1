#!/usr/bin/env pwsh
# GOAT System Installer - GitHub Copilot CLI (PowerShell)
#
# WARNING: Only install on systems you own or have permission to modify.
# This script is for personal development environments only.
#
# Installs the standalone GitHub Copilot CLI (copilot) via npm.
# Auth happens on first run via /login - no pre-auth required.
# Run this script in PowerShell on Windows, macOS, or Linux.

function Test-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
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

function Get-OsName {
    if (Get-Variable -Name IsWindows -Scope Global -ErrorAction SilentlyContinue) {
        if ($IsWindows) { return "Windows" }
        if ($IsMacOS) { return "macOS" }
        if ($IsLinux) { return "Linux" }
    }
    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) { return "Windows" }
    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)) { return "macOS" }
    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Linux)) { return "Linux" }
    return "Unknown"
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
            # Update current session
            $env:PATH = "$binPath;$env:PATH"
            # Persist for user
            $currentUserPath = [Environment]::GetEnvironmentVariable("PATH", "User")
            if (-not ($currentUserPath -split ';' | Where-Object { $_ -ieq $binPath })) {
                [Environment]::SetEnvironmentVariable("PATH", "$currentUserPath;$binPath", "User")
            }
        }
    }
}

Write-Host "Starting GitHub Copilot CLI installation process..." -ForegroundColor Cyan
Write-Host "This will install the standalone Copilot CLI from GitHub" -ForegroundColor Yellow

$os = Get-OsName
Write-Host "`nDetected OS: $os" -ForegroundColor Cyan

# Check if Node.js is installed (required for npm)
Write-Host "`nChecking for Node.js installation..." -ForegroundColor Yellow

if (Test-Command node) {
    $nodeVersion = node --version
    Write-Host "Node.js is already installed ($nodeVersion)" -ForegroundColor Green

    if (Test-Command npm) {
        $npmVersion = npm --version
        Write-Host "npm is already installed ($npmVersion)" -ForegroundColor Green
    } else {
        Write-Host "npm is not found. Please reinstall Node.js." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Node.js is required for GitHub Copilot CLI installation." -ForegroundColor Red
    Write-Host "Please install Node.js first (or enable it in your Forge config)." -ForegroundColor Red
    exit 1
}

# Add npm global bin early so new installs land on PATH
Ensure-NpmGlobalPath

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Installing GitHub Copilot CLI via npm" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

npm install -g @github/copilot --loglevel=error --no-audit --no-fund
if ($LASTEXITCODE -ne 0) {
    $pkgPresent = npm list -g @github/copilot --depth=0 2>$null
    if (-not $pkgPresent) {
        Write-Host "`nError installing GitHub Copilot CLI" -ForegroundColor Red
        Write-Host "`nTroubleshooting steps:" -ForegroundColor Yellow
        Write-Host "1. Check internet connection" -ForegroundColor White
        Write-Host "2. npm config list" -ForegroundColor White
        Write-Host "3. Try: npm install -g @github/copilot" -ForegroundColor White
        exit 1
    } else {
        Write-Host "npm reported an error, but '@github/copilot' appears installed. Continuing to PATH verification..." -ForegroundColor Yellow
    }
}

# Ensure npm global bin is on PATH (helps new shells find copilot.cmd)
Ensure-NpmGlobalPath

Write-Host "`nVerifying installation..." -ForegroundColor Yellow
if (Test-Command copilot) {
    Write-Host "GitHub Copilot CLI installed successfully!" -ForegroundColor Green
    copilot --version 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Version command not available yet" -ForegroundColor Yellow
    }
    Show-PathPrefixWarning

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Next Steps:" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "1. Start the CLI: copilot" -ForegroundColor White
    Write-Host "2. On first run, use /login to authenticate with GitHub" -ForegroundColor White
    Write-Host "3. Use /model to select an AI model" -ForegroundColor White
    Write-Host "4. Run copilot --help for commands" -ForegroundColor White
} else {
    Write-Host "`nGitHub Copilot CLI installed but command not found in PATH." -ForegroundColor Yellow
    Write-Host "You may need to:" -ForegroundColor Yellow
    Write-Host "1. Restart your terminal" -ForegroundColor White
    Write-Host "2. Or add the npm global bin directory to your PATH" -ForegroundColor White
    Write-Host "3. Check npm global directory: npm config get prefix" -ForegroundColor White
}

Write-Host "`nInstallation process completed!" -ForegroundColor Green
