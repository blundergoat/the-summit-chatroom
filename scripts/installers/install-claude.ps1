#!/usr/bin/env pwsh
# GOAT System Installer - Claude Code (PowerShell)
# Installs Claude Code using the native binary method (recommended)
# Falls back to npm if native installation fails
# Run this script in PowerShell on Windows, macOS, or Linux.

param(
    [switch]$UseNpm,
    [switch]$Force
)

function Test-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-ClaudeInstallationType {
    if (-not (Test-Command claude)) {
        return $null
    }

    try {
        $claudePath = (Get-Command claude -ErrorAction SilentlyContinue).Source
        if ($claudePath -match '\.claude[/\\]local[/\\]bin') {
            return "native"
        } elseif ($claudePath -match 'npm|node_modules') {
            return "npm-global"
        } else {
            return "unknown"
        }
    } catch {
        return "unknown"
    }
}

function Install-ClaudeNative {
    Write-Host "Installing Claude Code using native binary installer..." -ForegroundColor Cyan

    if ($IsWindows -or $env:OS -match "Windows") {
        # Windows: Use the official PowerShell installer
        Write-Host "Downloading and running official installer for Windows..." -ForegroundColor Yellow
        try {
            # The official installer URL
            $installerUrl = "https://claude.ai/install.ps1"
            Write-Host "Fetching installer from: $installerUrl" -ForegroundColor Gray

            # Download and execute
            $script = Invoke-RestMethod -Uri $installerUrl -UseBasicParsing
            Invoke-Expression $script
            return $true
        } catch {
            Write-Host "Native installer failed: $_" -ForegroundColor Red
            return $false
        }
    } elseif ($IsMacOS) {
        # macOS: Use curl installer
        Write-Host "Running official installer for macOS..." -ForegroundColor Yellow
        try {
            bash -c 'curl -fsSL https://claude.ai/install.sh | sh'
            return $LASTEXITCODE -eq 0
        } catch {
            Write-Host "Native installer failed: $_" -ForegroundColor Red
            return $false
        }
    } elseif ($IsLinux) {
        # Linux: Use curl installer
        Write-Host "Running official installer for Linux..." -ForegroundColor Yellow
        try {
            bash -c 'curl -fsSL https://claude.ai/install.sh | sh'
            return $LASTEXITCODE -eq 0
        } catch {
            Write-Host "Native installer failed: $_" -ForegroundColor Red
            return $false
        }
    }

    return $false
}

function Install-ClaudeNpm {
    $packageName = if ($env:CLAUDE_NPM_PACKAGE) { $env:CLAUDE_NPM_PACKAGE } else { "@anthropic-ai/claude-code" }

    Write-Host "Installing Claude Code via npm ($packageName)..." -ForegroundColor Cyan

    # Check for Node.js
    if (-not (Test-Command node)) {
        Write-Host "Node.js is required for npm installation." -ForegroundColor Red
        $installNode = Read-Host "Would you like to install Node.js? (y/n)"
        if ($installNode -ne "y") {
            return $false
        }

        if ($IsWindows -or $env:OS -match "Windows") {
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
                Write-Host "Homebrew not found. Please install Node.js manually." -ForegroundColor Yellow
                return $false
            }
        }

        if (-not (Test-Command node)) {
            Write-Host "Node.js installation failed." -ForegroundColor Red
            return $false
        }
    }

    Write-Host "Node.js version: $((node --version))" -ForegroundColor Gray

    # Ensure npm global path is in PATH
    $npmPrefix = (& npm prefix -g 2>$null)
    if ($npmPrefix) {
        $binPath = if ($IsWindows -or $env:OS -match "Windows") { $npmPrefix } else { Join-Path $npmPrefix "bin" }
        if (-not ($env:PATH -split [IO.Path]::PathSeparator | Where-Object { $_ -ieq $binPath })) {
            $env:PATH = "$binPath$([IO.Path]::PathSeparator)$env:PATH"
        }
    }

    # Install via npm
    npm install -g $packageName
    if ($LASTEXITCODE -ne 0) {
        Write-Host "npm installation failed." -ForegroundColor Red
        return $false
    }

    # After npm install, migrate to native if possible
    Write-Host "`nMigrating to native installation for better performance..." -ForegroundColor Yellow
    if (Test-Command claude) {
        try {
            claude install 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Successfully migrated to native installation!" -ForegroundColor Green
            }
        } catch {
            Write-Host "Migration to native skipped (npm installation will work fine)." -ForegroundColor Gray
        }
    }

    return $true
}

# =============================================================================
# Main Installation Flow
# =============================================================================

Write-Host "`n=== Claude Code Installer ===" -ForegroundColor Cyan
Write-Host "This will install Claude Code on your system.`n" -ForegroundColor Yellow

# Detect OS
$osName = if ($IsMacOS) { "macOS" } elseif ($IsLinux) { "Linux" } elseif ($IsWindows -or $env:OS -match "Windows") { "Windows" } else { "Unknown" }
Write-Host "Detected OS: $osName" -ForegroundColor Cyan

# Check for existing installation
$existingType = Get-ClaudeInstallationType
if ($existingType) {
    $claudePath = (Get-Command claude -ErrorAction SilentlyContinue).Source
    $claudeVersion = claude --version 2>$null | Select-Object -First 1

    Write-Host "`nExisting installation detected:" -ForegroundColor Yellow
    Write-Host "  Type: $existingType" -ForegroundColor White
    Write-Host "  Path: $claudePath" -ForegroundColor White
    Write-Host "  Version: $claudeVersion" -ForegroundColor White

    if (-not $Force) {
        $proceed = Read-Host "`nDo you want to reinstall/upgrade? (y/n)"
        if ($proceed -ne "y") {
            Write-Host "Installation cancelled." -ForegroundColor Yellow
            exit 0
        }
    }

    # If existing is npm and we want native, migrate
    if ($existingType -eq "npm-global" -and -not $UseNpm) {
        Write-Host "`nMigrating from npm to native installation..." -ForegroundColor Cyan
        try {
            claude install
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Migration successful!" -ForegroundColor Green
                # Uninstall npm version
                $packageName = if ($env:CLAUDE_NPM_PACKAGE) { $env:CLAUDE_NPM_PACKAGE } else { "@anthropic-ai/claude-code" }
                Write-Host "Removing npm package to avoid conflicts..." -ForegroundColor Yellow
                npm uninstall -g $packageName 2>$null

                # Verify
                Write-Host "`n=== Installation Complete ===" -ForegroundColor Green
                $newType = Get-ClaudeInstallationType
                Write-Host "Installation type: $newType" -ForegroundColor White
                claude --version 2>$null
                exit 0
            }
        } catch {
            Write-Host "Migration failed, will do fresh install." -ForegroundColor Yellow
        }
    }
}

# Determine installation method
$installSuccess = $false

if ($UseNpm) {
    Write-Host "`nUsing npm installation method (as requested)..." -ForegroundColor Yellow
    $installSuccess = Install-ClaudeNpm
} else {
    # Try native first (recommended)
    Write-Host "`nAttempting native binary installation (recommended)..." -ForegroundColor Yellow
    $installSuccess = Install-ClaudeNative

    if (-not $installSuccess) {
        Write-Host "`nNative installation failed. Falling back to npm..." -ForegroundColor Yellow
        $installSuccess = Install-ClaudeNpm
    }
}

if (-not $installSuccess) {
    Write-Host "`n=== Installation Failed ===" -ForegroundColor Red
    Write-Host "Troubleshooting steps:" -ForegroundColor Yellow
    Write-Host "  1. Check your internet connection" -ForegroundColor White
    Write-Host "  2. Try running as Administrator (Windows) or with sudo (Linux/macOS)" -ForegroundColor White
    Write-Host "  3. Try manual installation: npm install -g @anthropic-ai/claude-code" -ForegroundColor White
    Write-Host "  4. Visit: https://docs.anthropic.com/claude-code" -ForegroundColor White
    exit 1
}

# Refresh PATH
if ($IsWindows -or $env:OS -match "Windows") {
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
}

# Add native bin to PATH if needed
$nativeBinPath = Join-Path $HOME ".claude/local/bin"
if ((Test-Path $nativeBinPath) -and -not ($env:PATH -split [IO.Path]::PathSeparator | Where-Object { $_ -ieq $nativeBinPath })) {
    $env:PATH = "$nativeBinPath$([IO.Path]::PathSeparator)$env:PATH"

    # Persist to user PATH on Windows
    if ($IsWindows -or $env:OS -match "Windows") {
        $currentUserPath = [Environment]::GetEnvironmentVariable("PATH", "User")
        if (-not ($currentUserPath -split ';' | Where-Object { $_ -ieq $nativeBinPath })) {
            [Environment]::SetEnvironmentVariable("PATH", "$nativeBinPath;$currentUserPath", "User")
            Write-Host "Added $nativeBinPath to user PATH" -ForegroundColor Gray
        }
    }
}

# Final verification
Write-Host "`n=== Verification ===" -ForegroundColor Cyan

if (Test-Command claude) {
    $finalType = Get-ClaudeInstallationType
    $finalPath = (Get-Command claude -ErrorAction SilentlyContinue).Source

    Write-Host "Claude Code installed successfully!" -ForegroundColor Green
    Write-Host "  Installation type: $finalType" -ForegroundColor White
    Write-Host "  Location: $finalPath" -ForegroundColor White
    claude --version 2>$null

    # Run doctor to check for issues
    Write-Host "`nRunning diagnostics..." -ForegroundColor Cyan
    claude doctor 2>$null

    Write-Host "`n=== Next Steps ===" -ForegroundColor Cyan
    Write-Host "  1. Start Claude Code:  claude" -ForegroundColor White
    Write-Host "  2. Authenticate:       claude login" -ForegroundColor White
    Write-Host "  3. Get help:           claude --help" -ForegroundColor White

    if ($finalType -eq "npm-global") {
        Write-Host "`nTip: Run 'claude install' to migrate to native binary for better performance." -ForegroundColor Yellow
    }
} else {
    Write-Host "WARNING: Claude command not found in PATH after installation." -ForegroundColor Yellow
    Write-Host "Try restarting your terminal, then run: claude --version" -ForegroundColor Yellow
}

Write-Host "`nInstallation complete!" -ForegroundColor Green
