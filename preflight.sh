#!/usr/bin/env bash
# Preflight check for the ODI Demo Builder session.
# Read-only: it changes nothing. It checks every prerequisite and, for anything
# missing or misconfigured, prints the exact command to fix it.
# Exit code 0 = everything ready. Non-zero = something needs attention.

set -uo pipefail

GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; YELLOW=$'\033[0;33m'; BOLD=$'\033[1m'; NC=$'\033[0m'
PASS=0; FAIL=0
FAILURES=()

ok()   { printf "  ${GREEN}PASS${NC}  %s\n" "$1"; PASS=$((PASS+1)); }
bad()  { printf "  ${RED}FAIL${NC}  %s\n" "$1"; FAIL=$((FAIL+1)); FAILURES+=("$2"); }
warn() { printf "  ${YELLOW}WARN${NC}  %s\n" "$1"; }
head2(){ printf "\n${BOLD}%s${NC}\n" "$1"; }

have() { command -v "$1" >/dev/null 2>&1; }

printf "${BOLD}ODI Demo Builder — preflight${NC}\n"
printf "Checking every prerequisite. Nothing is modified.\n"

# ---------------------------------------------------------------------------
head2 "0. Homebrew (package manager)"
if have brew; then
  ok "brew installed ($(brew --version | head -1))"
else
  bad "Homebrew not found" 'Install Homebrew: /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
fi

# ---------------------------------------------------------------------------
head2 "a/b. Claude Code CLI + auth"
if have claude; then
  ok "claude installed ($(claude --version 2>/dev/null | head -1))"
  if claude whoami >/dev/null 2>&1; then
    ok "claude authenticated ($(claude whoami 2>/dev/null | head -1))"
  else
    bad "claude not authenticated" "claude login"
  fi
else
  bad "claude not found" "brew install claude-code   # or: npm install -g @anthropic-ai/claude-code"
fi

# ---------------------------------------------------------------------------
head2 "c. ODI Demo Builder skill"
SKILL="$HOME/.claude/skills/odi-demo-builder/SKILL.md"
LOOSE="$HOME/.claude/skills/odi-demo-builder.md"
if [[ -f "$SKILL" ]]; then
  ok "skill installed at ~/.claude/skills/odi-demo-builder/SKILL.md"
  if [[ -f "$LOOSE" ]]; then
    warn "stale loose file ~/.claude/skills/odi-demo-builder.md present — remove it: rm ~/.claude/skills/odi-demo-builder.md"
  fi
elif [[ -f "$LOOSE" ]]; then
  bad "skill is a loose .md file and will NOT load" "./install.sh   # moves it into the correct SKILL.md folder"
else
  bad "skill not installed" "./install.sh"
fi

# ---------------------------------------------------------------------------
head2 "d. Git"
if have git; then
  ok "git installed ($(git --version))"
  if git config --global user.email >/dev/null 2>&1 && [[ -n "$(git config --global user.email)" ]]; then
    ok "git identity set ($(git config --global user.email))"
  else
    bad "git identity not set" 'git config --global user.name "Your Name" && git config --global user.email "you@fivetran.com"'
  fi
else
  bad "git not found" "brew install git"
fi

# ---------------------------------------------------------------------------
head2 "e. GitHub CLI"
if have gh; then
  ok "gh installed ($(gh --version | head -1))"
  if gh auth status >/dev/null 2>&1; then
    ok "gh authenticated"
  else
    bad "gh not authenticated" "gh auth login   # choose GitHub.com, HTTPS, browser"
  fi
else
  bad "gh not found" "brew install gh && gh auth login"
fi

# ---------------------------------------------------------------------------
head2 "f. 1Password CLI"
if have op; then
  ok "op installed ($(op --version 2>/dev/null))"
  if op whoami >/dev/null 2>&1; then
    ok "op signed in"
  else
    bad "op not signed in" "op signin"
  fi
else
  bad "op not found" "brew install 1password-cli && op signin"
fi

# ---------------------------------------------------------------------------
head2 "g. Fivetran API key"
# Load .env if present so they can use either env vars or a project .env file.
if [[ -f .env ]]; then set -a; . ./.env; set +a; fi
if [[ -n "${FIVETRAN_API_KEY:-}" && -n "${FIVETRAN_API_SECRET:-}" ]]; then
  if have curl; then
    CODE=$(curl -s -u "$FIVETRAN_API_KEY:$FIVETRAN_API_SECRET" https://api.fivetran.com/v1/groups \
            | python3 -c "import sys,json;print(json.load(sys.stdin).get('code',''))" 2>/dev/null)
    if [[ "$CODE" == "Success" ]]; then
      ok "Fivetran API key works (groups returned Success)"
    else
      bad "Fivetran key set but API call failed (check key/secret)" 'verify FIVETRAN_API_KEY / FIVETRAN_API_SECRET at fivetran.com -> avatar -> API key'
    fi
  else
    warn "curl missing, cannot test Fivetran key"
  fi
else
  bad "FIVETRAN_API_KEY / FIVETRAN_API_SECRET not set" 'add to ~/.zshrc: export FIVETRAN_API_KEY="..."; export FIVETRAN_API_SECRET="..."; then: source ~/.zshrc'
fi

# ---------------------------------------------------------------------------
head2 "h. Terraform"
if have terraform; then
  ok "terraform installed ($(terraform version | head -1))"
else
  bad "terraform not found" "brew install terraform"
fi

# ---------------------------------------------------------------------------
head2 "i. AWS CLI"
if have aws; then
  ok "aws installed ($(aws --version 2>&1))"
  if aws sts get-caller-identity >/dev/null 2>&1; then
    ok "aws credentials valid ($(aws sts get-caller-identity --query Account --output text 2>/dev/null))"
  else
    bad "aws credentials not configured" "aws configure   # Access Key, Secret, region us-east-1, output json"
  fi
else
  bad "aws not found" "brew install awscli && aws configure"
fi

# ---------------------------------------------------------------------------
head2 "j. Node.js 20+"
if have node; then
  NODE_MAJOR=$(node -p "process.versions.node.split('.')[0]" 2>/dev/null || echo 0)
  if [[ "$NODE_MAJOR" -ge 20 ]]; then
    ok "node $(node --version) (>= 20)"
  else
    bad "node $(node --version) is below 20" "brew install node@20 && brew link node@20 --force"
  fi
else
  bad "node not found" "brew install node@20 && brew link node@20 --force"
fi

# ---------------------------------------------------------------------------
head2 "k. dbt CLI"
if have dbt; then
  ok "dbt installed ($(dbt --version 2>/dev/null | head -1))"
else
  bad "dbt not found" "pip install dbt-core dbt-duckdb   # plus dbt-snowflake or dbt-athena-community if targeting those"
fi

# ---------------------------------------------------------------------------
printf "\n${BOLD}Summary:${NC} ${GREEN}%d passed${NC}, ${RED}%d to fix${NC}\n" "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  printf "\n${BOLD}Fix these before the session:${NC}\n"
  for f in "${FAILURES[@]}"; do printf "  - ${YELLOW}%s${NC}\n" "$f"; done
  printf "\nTip: run ${BOLD}./setup.sh${NC} to auto-install the Homebrew-based tools, then re-run ${BOLD}./preflight.sh${NC}.\n"
  printf "Still stuck? Paste this output in the shared Slack channel before the session.\n"
  exit 1
fi
printf "\n${GREEN}All set. You are ready for the session.${NC}\n"
printf "Last step: restart Claude Code, then run: claude skill list | grep odi-demo-builder\n"
