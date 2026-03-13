#!/usr/bin/env bash
# Invoice Parser - Linux (Ubuntu) Dependency Installer
# Installs Python 3, Tesseract OCR, Poppler, and Python requirements.
#
# Usage:
#   chmod +x install.sh && ./install.sh
# Or one-liner:
#   curl -fsSL "https://your-raw-url/install.sh" | bash

set -euo pipefail

# ── Helpers ──────────────────────────────────────────────────────────────────

CYAN='\033[0;36m'
DARK_CYAN='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
WHITE='\033[1;37m'
RESET='\033[0m'

write_header() {
    local text="$1"
    local line
    line=$(printf '─%.0s' $(seq 1 ${#text}))
    echo ""
    echo -e "  ${CYAN}${text}${RESET}"
    echo -e "  ${DARK_CYAN}${line}${RESET}"
}

write_ok()   { echo -e "  ${GREEN}[OK]  $1${RESET}"; }
write_info() { echo -e "  ${YELLOW}[>>]  $1${RESET}"; }
write_fail() { echo -e "  ${RED}[!!]  $1${RESET}"; }

# Run apt quietly; elevate with sudo only if not already root
apt_install() {
    write_info "Installing: $*"
    if [[ $EUID -eq 0 ]]; then
        apt-get install -y -qq "$@"
    else
        sudo apt-get install -y -qq "$@"
    fi
}

apt_update() {
    write_info "Updating package lists..."
    if [[ $EUID -eq 0 ]]; then
        apt-get update -qq
    else
        sudo apt-get update -qq
    fi
}

# pip install wrapper — handles Ubuntu 23.04+ externally-managed environments
pip_install() {
    python3 -m pip install --quiet --break-system-packages "$@" 2>/dev/null \
        || python3 -m pip install --quiet "$@"
}

# ── Python ───────────────────────────────────────────────────────────────────

write_header "Python"

if command -v python3 &>/dev/null; then
    ver=$(python3 --version 2>&1)
    write_ok "Already installed: $ver"
else
    apt_update
    apt_install python3 python3-pip python3-venv
    ver=$(python3 --version 2>&1)
    write_ok "Installed: $ver"
fi

# Ensure pip is available
if ! python3 -m pip --version &>/dev/null; then
    write_info "pip not found — installing..."
    apt_install python3-pip
fi

write_info "Upgrading pip..."
pip_install --upgrade pip
write_ok "pip: $(python3 -m pip --version)"

# ── Tesseract OCR ────────────────────────────────────────────────────────────

write_header "Tesseract OCR"

if command -v tesseract &>/dev/null; then
    tess_ver=$(tesseract --version 2>&1 | head -1)
    write_ok "Already installed: $tess_ver"
else
    apt_update
    # English + Spanish language data included; add more packs as needed
    apt_install tesseract-ocr tesseract-ocr-eng tesseract-ocr-spa

    if command -v tesseract &>/dev/null; then
        tess_ver=$(tesseract --version 2>&1 | head -1)
        write_ok "Installed: $tess_ver"
    else
        write_fail "Tesseract not found after install."
        exit 1
    fi
fi

# ── Poppler ───────────────────────────────────────────────────────────────────

write_header "Poppler (pdf2image)"

if command -v pdftoppm &>/dev/null; then
    write_ok "Already installed: $(command -v pdftoppm)"
else
    apt_update
    apt_install poppler-utils

    if command -v pdftoppm &>/dev/null; then
        write_ok "Installed: $(command -v pdftoppm)"
    else
        write_fail "Poppler not found after install."
        exit 1
    fi
fi

# ── Python packages ──────────────────────────────────────────────────────────

write_header "Python packages (requirements.txt)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQ_FILE="$SCRIPT_DIR/requirements.txt"

if [[ -f "$REQ_FILE" ]]; then
    write_info "Found requirements.txt — installing..."
    pip_install -r "$REQ_FILE"
    write_ok "All packages installed."
else
    write_info "No requirements.txt found alongside the script — skipping pip install."
    write_info "Run manually:  pip install -r requirements.txt"
fi

# ── Done ─────────────────────────────────────────────────────────────────────

write_header "Setup complete"
write_ok "Python   : $(python3 --version 2>&1)"
write_ok "Tesseract: $(tesseract --version 2>&1 | head -1)"
write_ok "Poppler  : $(command -v pdftoppm)"
echo ""
echo -e "  ${WHITE}You're ready to use invoice-parser.${RESET}"
echo ""
