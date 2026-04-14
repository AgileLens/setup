#!/bin/bash
# ============================================================================
# Agile Lens — macOS Bootstrap Script
# Sets up a new team member's Mac with Claude Code, the shared Knowledge Base,
# auto-sync, KB viewer, and all hooks.
#
# Usage:
#   curl -sL <raw-url-to-this-file> | bash
#   — or —
#   bash bootstrap-mac.sh
# ============================================================================

set -euo pipefail

# ── Colors & helpers ────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail()    { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }
ask()     { read -rp "$(echo -e "${BOLD}$1${NC}") " "$2"; }
confirm() { read -rp "$(echo -e "${BOLD}$1 [Y/n]${NC}") " yn; [[ -z "$yn" || "$yn" =~ ^[Yy] ]]; }

KB_REPO="https://github.com/AgileLens/agile-lens-kb.git"
KB_DIR="$HOME/knowledge"
CLAUDE_DIR="$HOME/.claude"
VIEWER_PORT=8765

echo ""
echo -e "${BOLD}=====================================${NC}"
echo -e "${BOLD}  Agile Lens — macOS Bootstrap${NC}"
echo -e "${BOLD}=====================================${NC}"
echo ""

# ── Step 0: Collect machine info ────────────────────────────────────────────
ask "Machine name (lowercase, e.g., alex-desktop):" MACHINE_NAME
MACHINE_NAME=$(echo "$MACHINE_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
ask "Brief role description (e.g., Development workstation):" MACHINE_ROLE
ask "Your name (for commit messages, e.g., Alex):" USER_DISPLAY_NAME

echo ""
info "Setting up: $MACHINE_NAME ($MACHINE_ROLE)"
echo ""

# ── Step 1: Install Homebrew (if missing) ───────────────────────────────────
if command -v brew &>/dev/null; then
    success "Homebrew already installed"
else
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Add brew to PATH for this session (Apple Silicon vs Intel)
    if [ -f /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -f /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
    success "Homebrew installed"
fi

# ── Step 2: Install prerequisites ───────────────────────────────────────────
info "Installing prerequisites (git, node, python, gh)..."

for pkg in git node python3 gh; do
    if command -v "$pkg" &>/dev/null; then
        success "$pkg already installed ($(command -v "$pkg"))"
    else
        case "$pkg" in
            node)    brew install node ;;
            python3) brew install python@3 ;;
            gh)      brew install gh ;;
            git)     brew install git ;;
        esac
        success "$pkg installed"
    fi
done

echo ""

# ── Step 3: GitHub authentication ───────────────────────────────────────────
if gh auth status &>/dev/null; then
    success "GitHub CLI already authenticated"
else
    info "Authenticating with GitHub (browser will open)..."
    gh auth login --web --git-protocol https
    success "GitHub authenticated"
fi

echo ""

# ── Step 4: Clone the KB ────────────────────────────────────────────────────
if [ -d "$KB_DIR/.git" ]; then
    success "KB already cloned at $KB_DIR"
    cd "$KB_DIR" && git pull --rebase origin master || true
else
    info "Cloning Knowledge Base..."
    git clone "$KB_REPO" "$KB_DIR"
    success "KB cloned to $KB_DIR"
fi

# Set git user for KB commits
cd "$KB_DIR"
git config user.name "$USER_DISPLAY_NAME"
git config user.email "$(gh api user -q .email 2>/dev/null || echo "$USER_DISPLAY_NAME@agilelens.dev")"

echo ""

# ── Step 5: Create .claude directory + symlink ──────────────────────────────
mkdir -p "$CLAUDE_DIR"

if [ -L "$CLAUDE_DIR/knowledge" ]; then
    success "Symlink already exists: $CLAUDE_DIR/knowledge -> $KB_DIR"
elif [ -d "$CLAUDE_DIR/knowledge" ]; then
    warn "$CLAUDE_DIR/knowledge exists as a directory — moving to $KB_DIR"
    rsync -a "$CLAUDE_DIR/knowledge/" "$KB_DIR/"
    rm -rf "$CLAUDE_DIR/knowledge"
    ln -s "$KB_DIR" "$CLAUDE_DIR/knowledge"
    success "Migrated and symlinked"
else
    ln -s "$KB_DIR" "$CLAUDE_DIR/knowledge"
    success "Symlink created: $CLAUDE_DIR/knowledge -> $KB_DIR"
fi

echo ""

# ── Step 6: Install Claude Code ─────────────────────────────────────────────
if command -v claude &>/dev/null; then
    success "Claude Code already installed ($(claude --version 2>/dev/null || echo 'unknown version'))"
else
    info "Installing Claude Code..."
    npm install -g @anthropic-ai/claude-code
    success "Claude Code installed"
fi

echo ""

# ── Step 7: Deploy hook scripts ─────────────────────────────────────────────
info "Installing hook scripts..."

cp "$KB_DIR/departments/engineering/hooks/kb-inbox-check.sh" "$CLAUDE_DIR/kb-inbox-check.sh"
chmod +x "$CLAUDE_DIR/kb-inbox-check.sh"

cp "$KB_DIR/departments/engineering/hooks/kb-session-end.sh" "$CLAUDE_DIR/kb-session-end.sh"
chmod +x "$CLAUDE_DIR/kb-session-end.sh"

success "Hook scripts installed"

# ── Step 8: Deploy settings.json ────────────────────────────────────────────
info "Configuring Claude Code settings..."

SETTINGS_FILE="$CLAUDE_DIR/settings.json"
cat > "$SETTINGS_FILE" << 'SETTINGS_EOF'
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/kb-inbox-check.sh",
            "timeout": 30,
            "statusMessage": "Checking KB inbox..."
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/kb-session-end.sh",
            "timeout": 30,
            "statusMessage": "Syncing KB changes..."
          }
        ]
      }
    ]
  },
  "env": {
    "KB_MACHINE_NAME": "PLACEHOLDER_MACHINE_NAME"
  },
  "permissions": {
    "defaultMode": "bypassPermissions",
    "deny": [
      "Bash(rm -rf /)",
      "Bash(sudo rm -rf *)"
    ]
  }
}
SETTINGS_EOF

# Replace placeholder with actual machine name
sed -i '' "s/PLACEHOLDER_MACHINE_NAME/$MACHINE_NAME/" "$SETTINGS_FILE"

success "settings.json configured"

# ── Step 9: Deploy CLAUDE.md ────────────────────────────────────────────────
info "Generating CLAUDE.md for $MACHINE_NAME..."

HOSTNAME_ACTUAL=$(hostname -s)
OS_VERSION=$(sw_vers -productVersion 2>/dev/null || echo "macOS")
CHIP=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")
RAM=$(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.0f GB", $1/1073741824}')

cat > "$CLAUDE_DIR/CLAUDE.md" << CLAUDE_EOF
# CLAUDE.md — Agile Lens Base Configuration

## This Machine

**Name:** $MACHINE_NAME
**Hostname:** $HOSTNAME_ACTUAL
**OS:** macOS $OS_VERSION
**Role:** $MACHINE_ROLE
**Hardware:** $CHIP, $RAM RAM

## Inbox & Trigger Check (on session start)

At the start of each session, pull the KB and check this machine's inbox and triggers:
\`\`\`
cd ~/knowledge && git pull origin master
\`\`\`
Then:
1. Read \`inbox/$MACHINE_NAME.md\` — process any pending items, mark done, and push.
2. Check \`triggers/\` for any files targeting \`$MACHINE_NAME\` with \`status: pending\` — claim, execute, and complete them. See \`triggers/README.md\` for the full protocol.

### Sending triggers to other machines
To request work from another machine, create a trigger file:
\`\`\`markdown
# triggers/<descriptive-id>.md
---
id: <descriptive-id>
created: <ISO timestamp>
source: $MACHINE_NAME
target: <machine-name>
priority: <low|normal|high|urgent>
status: pending
---
## Task
<What needs to be done>
## Result
_Pending_
\`\`\`
Commit and push. The target machine will pick it up on its next session start or cron run.

## Identity

You are an autonomous engineering agent working within the Agile Lens environment, not an assistant waiting for instructions.
You have agency. Use it. When a task is ambiguous, investigate before asking.
When you finish something, look for what's next. When nothing is next, improve what exists.

## Knowledge Base

A persistent, shared knowledge base lives at \`~/knowledge/\` (with a symlink at \`~/.claude/knowledge/\`). It is the single source of truth for Agile Lens context.

**Every session should use it:**
- **Read before you work.** Check the KB first. Start with \`~/knowledge/CLAUDE.md\` for routing.
- **Write back as you work.** Update the KB with new facts, decisions, progress.
- **Daily logs are mandatory.** Append to \`~/knowledge/daily/YYYY-MM-DD.md\` at session end.
- **Commit and push.** After writing to the KB, always \`git add\`, \`commit\`, and \`push\`.

Key paths:
| Need | Path |
|---|---|
| Navigation guide | \`~/knowledge/CLAUDE.md\` |
| Business context | \`~/knowledge/context/\` |
| Writing style | \`~/knowledge/skills-ref/writing/\` |
| Infrastructure | \`~/knowledge/departments/engineering/\` |
| Daily logs | \`~/knowledge/daily/\` |
| Decisions | \`~/knowledge/intelligence/decisions/\` |
| Active projects | \`~/knowledge/projects/\` |
CLAUDE_EOF

success "CLAUDE.md generated"

echo ""

# ── Step 10: Set up auto-sync (cron) ────────────────────────────────────────
info "Setting up KB auto-sync (every 15 minutes)..."

SYNC_SCRIPT="$KB_DIR/kb-sync.sh"
chmod +x "$SYNC_SCRIPT"

CRON_LINE="*/15 * * * * KB_MACHINE_NAME=$MACHINE_NAME $SYNC_SCRIPT"
EXISTING_CRON=$(crontab -l 2>/dev/null || true)

if echo "$EXISTING_CRON" | grep -q "kb-sync.sh"; then
    success "Cron job already exists"
else
    (echo "$EXISTING_CRON"; echo "$CRON_LINE") | crontab -
    success "Cron job installed (every 15 minutes)"
fi

echo ""

# ── Step 11: Set up KB viewer ───────────────────────────────────────────────
info "Setting up KB viewer..."

# Build initial manifest
cd "$KB_DIR/_viewer"
python3 build-manifest.py
success "KB manifest built"

# Install http-server via npm
if command -v http-server &>/dev/null; then
    success "http-server already installed"
else
    npm install -g http-server
    success "http-server installed"
fi

# Create LaunchAgent for viewer auto-start
PLIST_PATH="$HOME/Library/LaunchAgents/dev.agilelens.kb-viewer.plist"
mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST_PATH" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>dev.agilelens.kb-viewer</string>
    <key>ProgramArguments</key>
    <array>
        <string>$(which http-server)</string>
        <string>$KB_DIR/_viewer</string>
        <string>-p</string>
        <string>$VIEWER_PORT</string>
        <string>-s</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/kb-viewer.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/kb-viewer.log</string>
</dict>
</plist>
PLIST_EOF

# Load the agent (start the viewer now)
launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"
success "KB viewer running at http://localhost:$VIEWER_PORT"

echo ""

# ── Step 12: Create inbox file for this machine ────────────────────────────
INBOX_FILE="$KB_DIR/inbox/$MACHINE_NAME.md"
if [ -f "$INBOX_FILE" ]; then
    success "Inbox file already exists"
else
    info "Creating inbox file..."
    cat > "$INBOX_FILE" << INBOX_EOF
---
title: "Inbox: $(echo "$MACHINE_NAME" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1')"
updated: $(date +%Y-%m-%d)
tags: [inbox, $MACHINE_NAME]
---

# $(echo "$MACHINE_NAME" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1') Inbox

Pending items for $MACHINE_NAME. Checked at session start.

## Pending

<!-- Nothing pending -->

## Done

<!-- Nothing archived -->
INBOX_EOF

    cd "$KB_DIR"
    git add "inbox/$MACHINE_NAME.md"
    git commit -m "chore(inbox): add inbox for $MACHINE_NAME"
    git push origin master
    success "Inbox file created and pushed"
fi

echo ""

# ── Step 13: Open viewer in browser ─────────────────────────────────────────
sleep 1
open "http://localhost:$VIEWER_PORT"

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}=====================================${NC}"
echo -e "${GREEN}${BOLD}  Setup Complete!${NC}"
echo -e "${BOLD}=====================================${NC}"
echo ""
echo -e "  Machine:       ${BOLD}$MACHINE_NAME${NC}"
echo -e "  KB location:   ${BOLD}$KB_DIR${NC}"
echo -e "  KB viewer:     ${BOLD}http://localhost:$VIEWER_PORT${NC}"
echo -e "  Auto-sync:     Every 15 minutes (cron)"
echo -e "  Claude config: ${BOLD}$CLAUDE_DIR/CLAUDE.md${NC}"
echo -e "  Settings:      ${BOLD}$CLAUDE_DIR/settings.json${NC}"
echo ""
echo -e "  ${BOLD}Quick start:${NC}"
echo -e "    claude                    # Start Claude Code"
echo -e "    cd ~/knowledge && git pull  # Manual KB sync"
echo -e "    open http://localhost:$VIEWER_PORT  # KB viewer"
echo ""
echo -e "  ${BOLD}Next steps:${NC}"
echo -e "    1. Run ${CYAN}claude${NC} to authenticate with Anthropic (first run)"
echo -e "    2. Start working — the KB and hooks are ready"
echo ""
