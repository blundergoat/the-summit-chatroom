#!/usr/bin/env pwsh
# GOAT System Installer - Kilo CLI (PowerShell)
# Installs the Kilo CLI and configures it for LM Studio (http://127.0.0.1:1234).
# Run this script in PowerShell on Windows, macOS, or Linux.

param()

$kiloPackage = if ($env:KILO_NPM_PACKAGE) { $env:KILO_NPM_PACKAGE } else { "@kilocode/cli" }
$kiloBaseUrl = if ($env:KILO_BASE_URL) { $env:KILO_BASE_URL } else { "http://127.0.0.1:1234" }
$kiloConfigDir = Join-Path (Join-Path $HOME ".kilocode") "cli"
$kiloConfigFile = Join-Path $kiloConfigDir "config.json"
$kiloToken = if ($env:KILO_TOKEN) { $env:KILO_TOKEN } else { "local-dev-token" }
$kiloProfileId = if ($env:KILO_PROFILE_ID) { $env:KILO_PROFILE_ID } else { "default" }
$kiloModel = if ($env:KILO_MODEL) { $env:KILO_MODEL } else { "lmstudio" }
$kiloOpenAiApiKey = if ($env:KILO_OPENAI_API_KEY) { $env:KILO_OPENAI_API_KEY } else { "local-dev-api-key" }
$pathSep = [IO.Path]::PathSeparator

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
        $pathParts = $env:PATH -split [IO.Path]::PathSeparator
        if (-not ($pathParts | Where-Object { $_ -eq $binPath })) {
            $env:PATH = "$binPath$pathSep$env:PATH"
            $currentUserPath = [Environment]::GetEnvironmentVariable("PATH", "User")
            if (-not (($currentUserPath -split [IO.Path]::PathSeparator) | Where-Object { $_ -eq $binPath })) {
                $newPath = if ($currentUserPath) { "$binPath$pathSep$currentUserPath" } else { $binPath }
                [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
            }
        }
    }
}

Write-Host "Starting Kilo CLI installation..." -ForegroundColor Cyan
Write-Host "npm package: $kiloPackage" -ForegroundColor Yellow
Write-Host "LM Studio endpoint: $kiloBaseUrl" -ForegroundColor Yellow

Write-Host "`nChecking for Node.js installation..." -ForegroundColor Yellow
if (Test-Command node) {
    Write-Host "Node.js is already installed ($((node --version)))" -ForegroundColor Green
    if (-not (Test-Command npm)) {
        Write-Host "npm is not found. Please reinstall Node.js." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Node.js is required for Kilo CLI." -ForegroundColor Red
    $installNode = Read-Host "Would you like to install Node.js? (y/n)"
    if ($installNode -ne "y") {
        Write-Host "Node.js is required. Exiting." -ForegroundColor Red
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

Write-Host "`nInstalling Kilo CLI via npm..." -ForegroundColor Cyan
npm install -g $kiloPackage
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error installing $kiloPackage. Set KILO_NPM_PACKAGE to the correct npm package if needed." -ForegroundColor Red
    exit 1
}

Write-Host "`nConfiguring Kilo CLI for LM Studio..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path $kiloConfigDir | Out-Null
$config = @{
    provider = "lm-studio"
    providers = @(
        @{
            id = "lm-studio"
            provider = "openai"
            type = "openai-compatible"
            baseUrl = $kiloBaseUrl
            kilocodeToken = $kiloToken
            openAiApiKey = $kiloOpenAiApiKey
            profiles = @(
                @{
                    id = $kiloProfileId
                    model = $kiloModel
                }
            )
        }
    )
}
$config | ConvertTo-Json -Depth 4 | Set-Content -Path $kiloConfigFile -Encoding UTF8
if (-not $IsWindows) {
    bash -lc "chmod 700 \"$kiloConfigDir\" && chmod 600 \"$kiloConfigFile\"" 2>$null | Out-Null
}
Write-Host "Saved configuration to $kiloConfigFile" -ForegroundColor Green

Write-Host "`nVerifying installation..." -ForegroundColor Yellow
if (Test-Command kilo) {
    Write-Host "Kilo CLI installed successfully!" -ForegroundColor Green
    kilo --version 2>$null
} else {
    Write-Host "Kilo command not found in PATH. You may need to restart your shell or add npm's global bin to PATH." -ForegroundColor Yellow
}

Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "1) Start the CLI: kilo" -ForegroundColor White
Write-Host "2) LM Studio endpoint is set to $kiloBaseUrl" -ForegroundColor White
Write-Host "3) Update config by changing KILO_BASE_URL or editing $kiloConfigFile" -ForegroundColor White
Write-Host "4) Run 'kilo --help' for commands" -ForegroundColor White

Write-Host "`nInstallation process completed!" -ForegroundColor Green
