# macOS Local Development Setup

This note covers the basic tools I use for Azure, Databricks, Terraform, Python, Git, GitHub, and VS Code work on macOS.

The preferred approach is to first check whether a tool is already available. If it is installed, skip it. If it is missing, install it. At the end, print all versions so the setup can be verified in one place.

---

## Status Legend

- 🟢 Installed / OK
- 🔵 Installing / Information
- 🟡 Manual check needed
- 🔴 Missing / Failed

---

## Tools Used

| Tool | Command | Why it is needed |
|---|---|---|
| Homebrew | `brew` | Package manager for installing development tools on macOS |
| Git | `git` | Source control for Terraform, Python, SQL, YAML and project files |
| Azure CLI | `az` | Azure login, subscription selection and resource validation |
| Terraform | `terraform` | Infrastructure as Code for Azure and Databricks resources |
| Python | `python3` | Automation, PySpark, testing and utility scripts |
| GitHub CLI | `gh` | GitHub login, repositories, pull requests and CI/CD related work |
| Databricks CLI | `databricks` | Databricks authentication, bundles, jobs and deployments |
| VS Code | `code` | Main editor for Terraform, Python, SQL, YAML and Markdown |

---

# Option 1 - Check First, Install Only What Is Missing

This is the option I normally use.

The script checks each tool first:

```text
Check tool
   |
   +-- Found -> skip install
   |
   +-- Missing -> install
                     |
                     v
              continue checks
                     |
                     v
              print versions
```

## Create the script

```bash
touch setup-macos-tools.sh
```

Open it:

```bash
code setup-macos-tools.sh
```

Add the following:

```bash
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
```

---

## Make the script executable

```bash
chmod +x setup-macos-tools.sh
```

Run it:

```bash
./setup-macos-tools.sh
```

The script can be run again later. Existing tools will be skipped.

Example:

```text
🟢 Homebrew already installed
🟢 Git already installed
🟢 Azure CLI already installed
🔵 Installing Terraform
🟢 Python already installed
🟢 GitHub CLI already installed
🔵 Installing Databricks CLI
🟢 VS Code already installed
```

# You will see like below once it is installed.
![macOS Development Setup](images/mac-setup.png)


# Option 2 - Install Everything Manually

Use this if the Mac is new and the tools are not installed yet.

## Update Homebrew

```bash
brew update
```

## Install Git, Azure CLI, Terraform, Python and GitHub CLI

```bash
brew install git azure-cli terraform python gh
```

## Add the Databricks Homebrew tap

```bash
brew tap databricks/tap
```

## Install Databricks CLI

```bash
brew install databricks
```

## Install Visual Studio Code

```bash
brew install --cask visual-studio-code
```

---

# Verify Versions

After installation, run:

```bash
brew --version
git --version
az version
terraform version
python3 --version
gh --version
databricks version
code --version
```

I normally check the binary locations as well:

```bash
which brew
which git
which az
which terraform
which python3
which gh
which databricks
which code
```

On an Apple Silicon Mac, Homebrew binaries are normally under:

```text
/opt/homebrew/bin
```

Check the machine architecture:

```bash
uname -m
```

Typical Apple Silicon output:

```text
arm64
```

---

# Login Checks

Installing the CLI tools is only the workstation setup. Azure, GitHub and Databricks still need authentication.

## Azure

```bash
az login
```

List subscriptions:

```bash
az account list --output table
```

Check the active subscription:

```bash
az account show --output table
```

Set the subscription if needed:

```bash
az account set --subscription "<SUBSCRIPTION_ID>"
```

---

## GitHub

```bash
gh auth login
```

Check login:

```bash
gh auth status
```

---

## Databricks

```bash
databricks auth login
```

Check configured profiles:

```bash
databricks auth profiles
```

---

# VS Code `code` Command

Sometimes VS Code is installed but this command does not work:

```bash
code .
```

If that happens:

1. Open Visual Studio Code.
2. Press `Command + Shift + P`.
3. Search for:

```text
Shell Command: Install 'code' command in PATH
```

4. Select it.
5. Reopen Terminal.

Then test:

```bash
code --version
```

---

# Basic Tool Notes

## Homebrew

Used to install and maintain local development packages.

Example:

```bash
brew install terraform
```

---

## Git

Used for version control.

Typical files tracked in a project:

```text
Terraform
Python
PySpark
SQL
YAML
JSON
Shell scripts
Markdown
GitHub Actions
```

---

## Azure CLI

Used mainly for Azure authentication and validation from the terminal.

Common commands:

```bash
az login
az account list --output table
az account show --output table
```

It is also useful when Terraform is using Azure CLI credentials during local development.

---

## Terraform

Used to create infrastructure from code.

Typical flow:

```bash
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

Example:

```hcl
resource "azurerm_resource_group" "main" {
  name     = "rg-databricks-dev"
  location = "eastus"
}
```

---

## Python

Used for:

```text
PySpark
automation
tests
data processing
Databricks notebooks and jobs
utility scripts
```

---

## GitHub CLI

Used for GitHub operations without leaving the terminal.

Examples:

```bash
gh auth login
gh repo create
gh pr list
gh pr create
```

---

## Databricks CLI

Used for Databricks command-line operations.

Examples:

```bash
databricks auth login
databricks bundle validate
databricks bundle deploy
databricks bundle run <job-name>
```

---

## Visual Studio Code

Main editor used for the project.

Typical file types:

```text
.tf
.py
.sql
.yml
.yaml
.json
.md
.sh
```

Open the current folder:

```bash
code .
```

---

# Final Check

Before moving to the Terraform or Databricks setup, I check the following:

```text
🟢 Homebrew
🟢 Git
🟢 Azure CLI
🟢 Terraform
🟢 Python
🟢 GitHub CLI
🟢 Databricks CLI
🟢 Visual Studio Code
```

Final command check:

```bash
brew --version
git --version
az version
terraform version
python3 --version
gh --version
databricks version
code --version
```

Once these commands are working, the local Mac setup is ready for the Azure and Databricks project.
