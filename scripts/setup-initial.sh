#!/bin/bash
# =============================================================================
# Initial Setup - Installs all dependencies for local development
# =============================================================================
# Usage: ./scripts/setup-initial.sh
#
# This script sets up the project for local development (outside Docker).
# It bootstraps common missing prerequisites when supported, copies the .env
# file if needed, installs PHP and Python dependencies, and prepares Ollama
# for local development when MODEL_PROVIDER=ollama.
#
# Supported auto-install package managers:
#   - apt-get
#   - Homebrew
#   - dnf
#   - yum
#
# Version requirements:
#   - PHP 8.2+
#   - Python 3.12+
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PYTHON_AGENT_DIR="$REPO_ROOT/strands_agents"
VENV_DIR="$PYTHON_AGENT_DIR/.venv"

# ── Colors ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

PASS="${GREEN}✔${RESET}"
FAIL="${RED}✘${RESET}"
ARROW="${BLUE}▸${RESET}"

ERRORS=0
PACKAGE_MANAGER=""
PACKAGE_MANAGER_LABEL=""
APT_UPDATED=false
OLLAMA_INSTALLED_BY_SETUP=false

# ── Helpers ─────────────────────────────────────────────────────────
step() {
    printf "  ${ARROW} %-44s" "$1"
}

pass() {
    local detail="${1:-}"
    if [[ -n "$detail" ]]; then
        echo -e "${PASS}  ${DIM}${detail}${RESET}"
    else
        echo -e "${PASS}"
    fi
}

fail() {
    local msg="$1"
    ERRORS=$((ERRORS + 1))
    echo -e "${FAIL}  ${RED}${msg}${RESET}"
}

warn() {
    local msg="$1"
    echo -e "${YELLOW}⚠${RESET}  ${DIM}${msg}${RESET}"
}

header() {
    echo ""
    echo -e "${BOLD}  The Summit - Initial Setup${RESET}"
    echo -e "  ${DIM}$(printf '─%.0s' {1..44})${RESET}"
    echo ""
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

run_as_root() {
    if [[ "$EUID" -eq 0 ]]; then
        "$@"
    elif command_exists sudo; then
        sudo "$@"
    else
        return 1
    fi
}

detect_package_manager() {
    if command_exists apt-get; then
        PACKAGE_MANAGER="apt"
        PACKAGE_MANAGER_LABEL="apt-get"
    elif command_exists brew; then
        PACKAGE_MANAGER="brew"
        PACKAGE_MANAGER_LABEL="brew"
    elif command_exists dnf; then
        PACKAGE_MANAGER="dnf"
        PACKAGE_MANAGER_LABEL="dnf"
    elif command_exists yum; then
        PACKAGE_MANAGER="yum"
        PACKAGE_MANAGER_LABEL="yum"
    else
        PACKAGE_MANAGER=""
        PACKAGE_MANAGER_LABEL=""
    fi
}

install_packages() {
    local packages=("$@")

    case "$PACKAGE_MANAGER" in
        apt)
            if [[ "$APT_UPDATED" == false ]]; then
                run_as_root apt-get update >/dev/null 2>&1 || return 1
                APT_UPDATED=true
            fi
            run_as_root apt-get install -y "${packages[@]}" >/dev/null 2>&1
            ;;
        brew)
            brew install "${packages[@]}" >/dev/null 2>&1
            ;;
        dnf)
            run_as_root dnf install -y "${packages[@]}" >/dev/null 2>&1
            ;;
        yum)
            run_as_root yum install -y "${packages[@]}" >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

php_version_string() {
    php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;' 2>/dev/null
}

php_version_ok() {
    local php_major
    local php_minor

    php_major=$(php -r 'echo PHP_MAJOR_VERSION;' 2>/dev/null) || return 1
    php_minor=$(php -r 'echo PHP_MINOR_VERSION;' 2>/dev/null) || return 1

    [[ "$php_major" -gt 8 ]] || { [[ "$php_major" -eq 8 ]] && [[ "$php_minor" -ge 2 ]]; }
}

python_version_string() {
    python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null
}

python_version_ok() {
    local py_major
    local py_minor

    py_major=$(python3 -c 'import sys; print(sys.version_info.major)' 2>/dev/null) || return 1
    py_minor=$(python3 -c 'import sys; print(sys.version_info.minor)' 2>/dev/null) || return 1

    [[ "$py_major" -gt 3 ]] || { [[ "$py_major" -eq 3 ]] && [[ "$py_minor" -ge 12 ]]; }
}

composer_version_string() {
    composer --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

pip_version_string() {
    if command_exists pip3; then
        pip3 --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1
    elif command_exists python3; then
        python3 -m pip --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1
    fi
}

install_php_runtime() {
    case "$PACKAGE_MANAGER" in
        apt)
            install_packages php-cli php-mbstring php-xml php-curl php-zip unzip
            ;;
        brew)
            install_packages php
            ;;
        dnf|yum)
            install_packages php-cli php-mbstring php-xml php-process unzip
            ;;
        *)
            return 1
            ;;
    esac
}

install_composer_tool() {
    case "$PACKAGE_MANAGER" in
        apt|brew|dnf|yum)
            install_packages composer
            ;;
        *)
            return 1
            ;;
    esac
}

install_python_runtime() {
    case "$PACKAGE_MANAGER" in
        apt)
            install_packages python3 python3-venv python3-pip
            ;;
        brew)
            install_packages python
            ;;
        dnf|yum)
            install_packages python3 python3-pip
            ;;
        *)
            return 1
            ;;
    esac
}

install_python_pip_support() {
    case "$PACKAGE_MANAGER" in
        apt)
            install_packages python3-pip python3-venv
            ;;
        brew)
            install_packages python
            ;;
        dnf|yum)
            install_packages python3-pip
            ;;
        *)
            return 1
            ;;
    esac
}

install_python_venv_support() {
    case "$PACKAGE_MANAGER" in
        apt)
            install_packages python3-venv
            ;;
        brew)
            install_packages python
            ;;
        dnf|yum)
            install_packages python3
            ;;
        *)
            return 1
            ;;
    esac
}

ensure_php() {
    local php_version

    step "PHP 8.2+"
    if command_exists php; then
        php_version="$(php_version_string)"
        if php_version_ok; then
            pass "v${php_version}"
        else
            fail "found v${php_version}, need 8.2+"
        fi
        return
    fi

    if install_php_runtime && command_exists php; then
        php_version="$(php_version_string)"
        if php_version_ok; then
            pass "v${php_version}, installed via ${PACKAGE_MANAGER_LABEL}"
        else
            fail "installed v${php_version}, need 8.2+"
        fi
        return
    fi

    if [[ -n "$PACKAGE_MANAGER_LABEL" ]]; then
        fail "not found - auto-install via ${PACKAGE_MANAGER_LABEL} failed"
    else
        fail "not found"
    fi
}

ensure_composer() {
    local composer_version

    step "Composer"
    if command_exists composer; then
        composer_version="$(composer_version_string)"
        pass "v${composer_version}"
        return
    fi

    if install_composer_tool && command_exists composer; then
        composer_version="$(composer_version_string)"
        pass "v${composer_version}, installed via ${PACKAGE_MANAGER_LABEL}"
        return
    fi

    if [[ -n "$PACKAGE_MANAGER_LABEL" ]]; then
        fail "not found - auto-install via ${PACKAGE_MANAGER_LABEL} failed"
    else
        fail "not found"
    fi
}

ensure_python() {
    local py_version

    step "Python 3.12+"
    if command_exists python3; then
        py_version="$(python_version_string)"
        if python_version_ok; then
            pass "v${py_version}"
        else
            fail "found v${py_version}, need 3.12+"
        fi
        return
    fi

    if install_python_runtime && command_exists python3; then
        py_version="$(python_version_string)"
        if python_version_ok; then
            pass "v${py_version}, installed via ${PACKAGE_MANAGER_LABEL}"
        else
            fail "installed v${py_version}, need 3.12+"
        fi
        return
    fi

    if [[ -n "$PACKAGE_MANAGER_LABEL" ]]; then
        fail "not found - auto-install via ${PACKAGE_MANAGER_LABEL} failed"
    else
        fail "not found"
    fi
}

ensure_pip_support() {
    local pip_version

    step "pip3"
    if command_exists pip3; then
        pip_version="$(pip_version_string)"
        pass "v${pip_version}"
        return
    fi

    if ! command_exists python3; then
        fail "python3 missing"
        return
    fi

    if python3 -m pip --version >/dev/null 2>&1; then
        pip_version="$(pip_version_string)"
        pass "v${pip_version} via python3 -m pip"
        return
    fi

    if python3 -m ensurepip --upgrade >/dev/null 2>&1 && python3 -m pip --version >/dev/null 2>&1; then
        pip_version="$(pip_version_string)"
        pass "v${pip_version}, bootstrapped"
        return
    fi

    if install_python_pip_support; then
        if command_exists pip3 || python3 -m pip --version >/dev/null 2>&1; then
            pip_version="$(pip_version_string)"
            pass "v${pip_version}, installed via ${PACKAGE_MANAGER_LABEL}"
            return
        fi
    fi

    if [[ -n "$PACKAGE_MANAGER_LABEL" ]]; then
        fail "not found - auto-install via ${PACKAGE_MANAGER_LABEL} failed"
    else
        fail "not found"
    fi
}

create_python_venv() {
    if python3 -m venv "$VENV_DIR" >/dev/null 2>&1; then
        return 0
    fi

    if install_python_venv_support && python3 -m venv "$VENV_DIR" >/dev/null 2>&1; then
        return 0
    fi

    return 1
}

detect_package_manager

# ── Prerequisite checks ────────────────────────────────────────────
header

echo -e "  ${BOLD}Checking prerequisites${RESET}"
echo ""

ensure_php
ensure_composer
ensure_python
ensure_pip_support

if [[ $ERRORS -gt 0 ]]; then
    echo ""
    echo -e "  ${RED}${BOLD}Cannot continue - ${ERRORS} prerequisite(s) missing${RESET}"
    echo ""
    exit 1
fi

# ── Environment file ───────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}Setting up environment${RESET}"
echo ""

step "Copy .env.example → .env"
if [[ -f "$REPO_ROOT/.env" ]]; then
    pass "already exists"
else
    cp "$REPO_ROOT/.env.example" "$REPO_ROOT/.env"
    pass "created"
fi

# ── PHP dependencies ───────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}Installing PHP dependencies${RESET}"
echo ""

step "composer install"
if install_output=$(cd "$REPO_ROOT" && composer install --no-interaction 2>&1); then
    pkg_count=$(cd "$REPO_ROOT" && composer show 2>/dev/null | wc -l)
    pass "${pkg_count} packages"
else
    fail "composer install failed"
    echo "$install_output" | tail -n 5 | while IFS= read -r line; do
        echo -e "    ${DIM}${line}${RESET}"
    done
fi

# ── Python dependencies ────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}Installing Python dependencies${RESET}"
echo ""

step "Create Python venv"
if [[ -f "$VENV_DIR/bin/python" ]]; then
    pass "already exists"
else
    if create_python_venv; then
        pass "created"
    else
        fail "failed to create venv"
    fi
fi

step "pip install -r requirements.txt"
if [[ -x "$VENV_DIR/bin/python" ]]; then
    if pip_output=$("$VENV_DIR/bin/python" -m pip install -r "$PYTHON_AGENT_DIR/requirements.txt" 2>&1); then
        pkg_count=$("$VENV_DIR/bin/python" -m pip list --format=columns 2>/dev/null | tail -n +3 | wc -l)
        pass "${pkg_count} packages"
    else
        fail "pip install failed"
        echo "$pip_output" | tail -n 5 | while IFS= read -r line; do
            echo -e "    ${DIM}${line}${RESET}"
        done
    fi
else
    fail "venv missing"
fi

# ── Ollama model ──────────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}Preparing Ollama${RESET}"
echo ""

MODEL_PROVIDER="$(grep -E '^MODEL_PROVIDER=' "$REPO_ROOT/.env" 2>/dev/null | head -1 | cut -d= -f2-)"
MODEL_PROVIDER="${MODEL_PROVIDER:-ollama}"

OLLAMA_MODEL="$(grep -E '^OLLAMA_MODEL=' "$REPO_ROOT/.env" 2>/dev/null | head -1 | cut -d= -f2-)"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen3:14b}"

if [[ "$MODEL_PROVIDER" != "ollama" ]]; then
    step "MODEL_PROVIDER"
    pass "${MODEL_PROVIDER} - skipping Ollama setup"
else
    if ! command_exists ollama; then
        warn "Ollama not found - running ./scripts/install-ollama.sh --model ${OLLAMA_MODEL}"
        echo ""
        if "$REPO_ROOT/scripts/install-ollama.sh" --model "$OLLAMA_MODEL"; then
            OLLAMA_INSTALLED_BY_SETUP=true
        else
            fail "Ollama install failed"
        fi
        echo ""
    fi

    step "Ollama installed"
    if command_exists ollama; then
        if [[ "$OLLAMA_INSTALLED_BY_SETUP" == true ]]; then
            pass "installed via install-ollama.sh"
        else
            pass
        fi
    else
        fail "not found — install from https://ollama.com"
    fi

    if [[ $ERRORS -eq 0 ]]; then
        step "Pull ${OLLAMA_MODEL}"
        if [[ "$OLLAMA_INSTALLED_BY_SETUP" == true ]]; then
            pass "already handled by install-ollama.sh"
        elif ollama pull "$OLLAMA_MODEL" >/dev/null 2>&1; then
            pass "pulled"
        else
            fail "ollama pull failed"
        fi
    fi
fi

# ── Summary ────────────────────────────────────────────────────────
echo ""
echo -e "  ${DIM}$(printf '─%.0s' {1..44})${RESET}"

if [[ $ERRORS -eq 0 ]]; then
    echo ""
    echo -e "  ${GREEN}${BOLD}Setup complete!${RESET}"
    echo ""
    echo -e "  ${DIM}Next steps:${RESET}"
    echo -e "    ${ARROW} Run quality checks:     ${BOLD}scripts/preflight-checks.sh${RESET}"
    echo -e "    ${ARROW} Start dev server:        ${BOLD}scripts/start-dev.sh${RESET}"
    echo -e "    ${ARROW} Python venv is at:       ${DIM}strands_agents/.venv${RESET}"
    echo ""
else
    echo ""
    echo -e "  ${RED}${BOLD}Setup finished with ${ERRORS} error(s)${RESET}"
    echo ""
    exit 1
fi
