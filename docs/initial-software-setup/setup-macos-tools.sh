#!/usr/bin/env bash

set -e

echo "=============================================="
echo "macOS development tools setup"
echo "=============================================="
echo ""

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# --------------------------------------------------
# Homebrew
# --------------------------------------------------

if command_exists brew; then
    echo "🟢 Homebrew already installed"
else
    echo "🔵 Installing Homebrew"

    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Homebrew path for Apple Silicon Macs
    if [ -x "/opt/homebrew/bin/brew" ]; then
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zprofile"
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
fi

echo ""
echo "🔵 Updating Homebrew"
brew update

# --------------------------------------------------
# Git
# --------------------------------------------------

if command_exists git; then
    echo "🟢 Git already installed"
else
    echo "🔵 Installing Git"
    brew install git
fi

# --------------------------------------------------
# Azure CLI
# --------------------------------------------------

if command_exists az; then
    echo "🟢 Azure CLI already installed"
else
    echo "🔵 Installing Azure CLI"
    brew install azure-cli
fi

# --------------------------------------------------
# Terraform
# --------------------------------------------------

if command_exists terraform; then
    echo "🟢 Terraform already installed"
else
    echo "🔵 Installing Terraform"
    brew install terraform
fi

# --------------------------------------------------
# Python
# --------------------------------------------------

if command_exists python3; then
    echo "🟢 Python already installed"
else
    echo "🔵 Installing Python"
    brew install python
fi

# --------------------------------------------------
# GitHub CLI
# --------------------------------------------------

if command_exists gh; then
    echo "🟢 GitHub CLI already installed"
else
    echo "🔵 Installing GitHub CLI"
    brew install gh
fi

# --------------------------------------------------
# Databricks CLI
# --------------------------------------------------

if command_exists databricks; then
    echo "🟢 Databricks CLI already installed"
else
    echo "🔵 Installing Databricks CLI"

    if ! brew tap | grep -q "^databricks/tap$"; then
        brew tap databricks/tap
    fi

    brew install databricks
fi

# --------------------------------------------------
# Visual Studio Code
# --------------------------------------------------

if command_exists code; then
    echo "🟢 VS Code already installed"
elif [ -d "/Applications/Visual Studio Code.app" ]; then
    echo "🟡 VS Code is installed, but 'code' is not in PATH"
else
    echo "🔵 Installing VS Code"
    brew install --cask visual-studio-code
fi

# --------------------------------------------------
# Version check
# --------------------------------------------------

echo ""
echo "=============================================="
echo "Installed versions"
echo "=============================================="
echo ""

echo "Homebrew:"
brew --version | head -n 1

echo ""
echo "Git:"
git --version

echo ""
echo "Azure CLI:"
az version

echo ""
echo "Terraform:"
terraform version

echo ""
echo "Python:"
python3 --version

echo ""
echo "GitHub CLI:"
gh --version | head -n 1

echo ""
echo "Databricks CLI:"
databricks version 2>/dev/null || databricks --version

echo ""
echo "VS Code:"
if command_exists code; then
    code --version | head -n 1
else
    echo "VS Code app installed, but 'code' command is not available in PATH"
fi

echo ""
echo "=============================================="
echo "Setup complete"
echo "=============================================="