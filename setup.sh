#!/usr/bin/env bash
# One-shot setup for the ODI Demo Builder session.
# Auto-installs the Homebrew-based prerequisites, installs the skill, then runs
# preflight. Things that need YOUR credentials (logins, API keys) can't be
# automated — preflight will tell you exactly which ones remain.
#
# Safe to run more than once: brew skips already-installed tools.

set -uo pipefail
cd "$(dirname "$0")"

BOLD=$'\033[1m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; NC=$'\033[0m'
say() { printf "\n${BOLD}==> %s${NC}\n" "$1"; }

# --- Homebrew ---------------------------------------------------------------
if ! command -v brew >/dev/null 2>&1; then
  say "Installing Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Make brew available in this shell (Apple Silicon default path).
  [[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
  [[ -x /usr/local/bin/brew ]] && eval "$(/usr/local/bin/brew shellenv)"
fi

# --- brew formulae ----------------------------------------------------------
brew_install() {
  if command -v "$1" >/dev/null 2>&1; then
    printf "  already have %s\n" "$1"
  else
    say "Installing $2"
    brew install "$2"
  fi
}

say "Installing CLI tools via Homebrew"
brew_install claude   claude-code
brew_install git      git
brew_install gh       gh
brew_install op       1password-cli
brew_install terraform terraform
brew_install aws      awscli

# Node 20 specifically.
NODE_MAJOR=$(command -v node >/dev/null 2>&1 && node -p "process.versions.node.split('.')[0]" 2>/dev/null || echo 0)
if [[ "${NODE_MAJOR:-0}" -lt 20 ]]; then
  say "Installing Node 20"
  brew install node@20
  brew link node@20 --force || true
else
  printf "  already have node %s\n" "$(node --version)"
fi

# dbt via pip (Homebrew dbt is discouraged).
if ! command -v dbt >/dev/null 2>&1; then
  say "Installing dbt (dbt-core + dbt-duckdb)"
  pip install dbt-core dbt-duckdb || pip3 install dbt-core dbt-duckdb || \
    printf "  ${YELLOW}pip install dbt failed — install manually: pip install dbt-core dbt-duckdb${NC}\n"
else
  printf "  already have dbt\n"
fi

# --- skill ------------------------------------------------------------------
say "Installing the odi-demo-builder skill"
./install.sh

# --- remaining manual steps -------------------------------------------------
cat <<'EOF'

==> Tools installed. A few things still need YOUR credentials — run these:
    claude login                 # Claude Code auth
    gh auth login                # GitHub.com, HTTPS, browser
    op signin                    # 1Password
    aws configure                # AWS keys, region us-east-1, output json
    git config --global user.name  "Your Name"
    git config --global user.email "you@fivetran.com"

    Fivetran API key — add to ~/.zshrc then `source ~/.zshrc`:
    export FIVETRAN_API_KEY="your_key_here"
    export FIVETRAN_API_SECRET="your_secret_here"
    (key/secret: fivetran.com -> avatar top-right -> API key)

EOF

say "Running preflight to show what is left"
./preflight.sh
