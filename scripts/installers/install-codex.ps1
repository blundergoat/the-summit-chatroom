#!/usr/bin/env pwsh
# GOAT System Installer - Codex CLI (PowerShell)
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

Write-Host "Starting Codex CLI installation process..." -ForegroundColor Cyan
Write-Host "This will install Codex CLI from OpenAI" -ForegroundColor Yellow

$os = Get-OsName
Write-Host "`nDetected OS: $os" -ForegroundColor Cyan

$brewAttempted = $false
if ($os -eq "macOS" -and (Test-Command brew)) {
    $brewAttempted = $true
    Write-Host "`nInstalling via Homebrew..." -ForegroundColor Yellow
    brew install codex
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Codex CLI installed successfully via Homebrew." -ForegroundColor Green
    } else {
        Write-Host "Homebrew installation failed. Falling back to npm." -ForegroundColor Yellow
    }
}

# Ensure Node.js/npm for npm installation path
if (-not $brewAttempted -or $LASTEXITCODE -ne 0) {
    Write-Host "`nChecking for Node.js installation..." -ForegroundColor Yellow
    if (Test-Command node) {
        Write-Host "Node.js is already installed ($((node --version)))" -ForegroundColor Green
        if (-not (Test-Command npm)) {
            Write-Host "npm is not found. Please reinstall Node.js." -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "Node.js is required for Codex CLI." -ForegroundColor Red
        $installNode = Read-Host "Would you like to install Node.js? (y/n)"
        if ($installNode -ne "y") {
            Write-Host "Node.js is required for Codex CLI. Exiting." -ForegroundColor Red
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

    # Add npm global bin early so new installs land on PATH
    Ensure-NpmGlobalPath



    Write-Host "`nInstalling Codex CLI via npm..." -ForegroundColor Cyan
    npm install -g @openai/codex
    if ($LASTEXITCODE -ne 0) {
        # If install failed but package already exists, continue to PATH/setup
        $pkgPresent = npm list -g @openai/codex --depth=0 2>$null
        if (-not $pkgPresent) {
            Write-Host "Error installing Codex CLI." -ForegroundColor Red
            Write-Host "Troubleshooting steps:" -ForegroundColor Yellow
            Write-Host "1) Check internet connection" -ForegroundColor White
            Write-Host "2) npm config list" -ForegroundColor White
            Write-Host "3) Try: npm install -g @openai/codex" -ForegroundColor White
            exit 1
        } else {
            Write-Host "npm reported an error, but '@openai/codex' appears installed. Continuing to PATH verification..." -ForegroundColor Yellow
        }
    }
}

# Ensure npm global bin is on PATH (helps new shells find codex.cmd)
Ensure-NpmGlobalPath

Write-Host "`nVerifying installation..." -ForegroundColor Yellow
if (Test-Command codex) {
    Write-Host "Codex CLI installed successfully!" -ForegroundColor Green
    codex --version 2>$null
    Show-PathPrefixWarning
    Write-Host "`nNext steps:" -ForegroundColor Cyan
    Write-Host "1) Start the CLI: codex" -ForegroundColor White
    Write-Host "2) Authenticate when prompted" -ForegroundColor White
    Write-Host "3) Run 'codex --help' for commands" -ForegroundColor White
} else {
    Write-Host "Codex CLI installed but command not found in PATH. Restart your terminal or add the npm global bin to PATH (npm config get prefix)." -ForegroundColor Yellow
}

Write-Host "`nInstallation process completed!" -ForegroundColor Green
