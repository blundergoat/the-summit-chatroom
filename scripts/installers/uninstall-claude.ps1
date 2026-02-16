#!/usr/bin/env pwsh
# GOAT System Uninstaller - Claude Code (PowerShell)
# Handles all installation types: native binary, npm-global, npm
# Run this script in PowerShell on Windows, macOS, or Linux.

param(
    [switch]$KeepConfig,
    [switch]$Force
)

function Test-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-ClaudeInstallationType {
    # Check if claude command exists and determine installation type
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

Write-Host "`n=== Claude Code Uninstaller ===" -ForegroundColor Cyan
Write-Host "This will remove Claude Code from your system.`n" -ForegroundColor Yellow

# Detect current installation
$installType = Get-ClaudeInstallationType
if ($installType) {
    Write-Host "Detected installation type: $installType" -ForegroundColor Cyan
    $claudePath = (Get-Command claude -ErrorAction SilentlyContinue).Source
    Write-Host "Claude location: $claudePath" -ForegroundColor Gray
} else {
    Write-Host "No Claude Code installation detected via PATH." -ForegroundColor Yellow
    Write-Host "Will attempt cleanup of known installation locations anyway.`n" -ForegroundColor Yellow
}

# Step 1: Uninstall native binary installation
Write-Host "`n[1/4] Checking for native binary installation..." -ForegroundColor Cyan
$nativePaths = @(
    (Join-Path $HOME ".claude/local"),
    (Join-Path $env:LOCALAPPDATA "Claude" -ErrorAction SilentlyContinue),
    (Join-Path $HOME ".local/bin/claude")
)

foreach ($path in $nativePaths) {
    if ($path -and (Test-Path $path)) {
        Write-Host "Found native installation at: $path" -ForegroundColor Yellow
        if ($Force -or (Read-Host "Remove native installation? (y/n)") -eq "y") {
            try {
                Remove-Item -Recurse -Force $path -ErrorAction Stop
                Write-Host "Removed: $path" -ForegroundColor Green
            } catch {
                Write-Host "Failed to remove $path - $_" -ForegroundColor Red
            }
        }
    }
}

# Also check for native bin in PATH locations
$nativeBinPath = Join-Path $HOME ".claude/local/bin"
if (Test-Path $nativeBinPath) {
    if ($Force -or (Read-Host "Remove native bin directory at $nativeBinPath? (y/n)") -eq "y") {
        Remove-Item -Recurse -Force $nativeBinPath -ErrorAction SilentlyContinue
        Write-Host "Removed: $nativeBinPath" -ForegroundColor Green
    }
}

# Step 2: Uninstall npm global package
Write-Host "`n[2/4] Checking for npm global installation..." -ForegroundColor Cyan
$packageName = if ($env:CLAUDE_NPM_PACKAGE) { $env:CLAUDE_NPM_PACKAGE } else { "@anthropic-ai/claude-code" }

if (Test-Command npm) {
    # Check if package is installed
    $npmList = npm list -g $packageName 2>$null
    if ($LASTEXITCODE -eq 0 -and $npmList -match $packageName) {
        Write-Host "Found npm package: $packageName" -ForegroundColor Yellow
        Write-Host "Uninstalling npm package..." -ForegroundColor Cyan
        npm uninstall -g $packageName
        if ($LASTEXITCODE -eq 0) {
            Write-Host "npm package uninstalled successfully." -ForegroundColor Green
        } else {
            Write-Host "npm uninstall may have encountered issues." -ForegroundColor Yellow
        }
    } else {
        Write-Host "npm package not found globally." -ForegroundColor Gray
    }
} else {
    Write-Host "npm not found, skipping npm uninstall." -ForegroundColor Gray
}

# Step 3: Clean up any remaining claude binaries in common locations
Write-Host "`n[3/4] Checking for stray binaries..." -ForegroundColor Cyan
$strayPaths = @(
    (Join-Path $env:APPDATA "npm/claude.cmd" -ErrorAction SilentlyContinue),
    (Join-Path $env:APPDATA "npm/claude" -ErrorAction SilentlyContinue),
    (Join-Path $HOME ".local/bin/claude"),
    "/usr/local/bin/claude"
)

foreach ($path in $strayPaths) {
    if ($path -and (Test-Path $path)) {
        Write-Host "Found stray binary: $path" -ForegroundColor Yellow
        if ($Force -or (Read-Host "Remove? (y/n)") -eq "y") {
            Remove-Item -Force $path -ErrorAction SilentlyContinue
            Write-Host "Removed: $path" -ForegroundColor Green
        }
    }
}

# Step 4: Remove configuration and cache directories (optional)
if (-not $KeepConfig) {
    Write-Host "`n[4/4] Configuration and cache cleanup..." -ForegroundColor Cyan
    $configPaths = @(
        (Join-Path $HOME ".claude"),
        (Join-Path $HOME ".config/claude"),
        (Join-Path $HOME ".config/anthropic"),
        (Join-Path $HOME ".cache/claude"),
        (Join-Path $env:LOCALAPPDATA "claude" -ErrorAction SilentlyContinue),
        (Join-Path $env:APPDATA "claude" -ErrorAction SilentlyContinue)
    )

    Write-Host "`nThe following directories contain Claude Code settings and cache:" -ForegroundColor Yellow
    $existingConfigs = $configPaths | Where-Object { $_ -and (Test-Path $_) }

    if ($existingConfigs.Count -eq 0) {
        Write-Host "No configuration directories found." -ForegroundColor Gray
    } else {
        foreach ($path in $existingConfigs) {
            Write-Host "  - $path" -ForegroundColor White
        }

        if ($Force) {
            $removeAll = "y"
        } else {
            $removeAll = Read-Host "`nRemove ALL configuration directories? (y/n/select)"
        }

        if ($removeAll -eq "y") {
            foreach ($path in $existingConfigs) {
                Remove-Item -Recurse -Force $path -ErrorAction SilentlyContinue
                Write-Host "Removed: $path" -ForegroundColor Green
            }
        } elseif ($removeAll -eq "select") {
            foreach ($path in $existingConfigs) {
                if ((Read-Host "Remove $path? (y/n)") -eq "y") {
                    Remove-Item -Recurse -Force $path -ErrorAction SilentlyContinue
                    Write-Host "Removed: $path" -ForegroundColor Green
                } else {
                    Write-Host "Skipped: $path" -ForegroundColor Yellow
                }
            }
        } else {
            Write-Host "Configuration directories preserved." -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "`n[4/4] Skipping config cleanup (-KeepConfig specified)" -ForegroundColor Gray
}

# Final verification
Write-Host "`n=== Verification ===" -ForegroundColor Cyan

# Refresh PATH to check if claude is still accessible
$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")

if (Test-Command claude) {
    $remainingPath = (Get-Command claude -ErrorAction SilentlyContinue).Source
    Write-Host "WARNING: Claude command still found at: $remainingPath" -ForegroundColor Yellow
    Write-Host "You may need to:" -ForegroundColor Yellow
    Write-Host "  1. Restart your terminal" -ForegroundColor White
    Write-Host "  2. Remove the file manually: $remainingPath" -ForegroundColor White
    Write-Host "  3. Remove the directory from PATH" -ForegroundColor White
} else {
    Write-Host "SUCCESS: Claude Code has been uninstalled!" -ForegroundColor Green
}

Write-Host "`nUninstall complete!" -ForegroundColor Green
Write-Host "To reinstall, run: .\install-claude.ps1`n" -ForegroundColor Gray
