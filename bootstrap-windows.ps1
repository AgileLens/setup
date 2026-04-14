# ============================================================================
# Agile Lens — Windows Bootstrap Script
# Sets up a new team member's Windows PC with Claude Code, the shared
# Knowledge Base, auto-sync, KB viewer, and all hooks.
#
# Usage (run as Administrator in PowerShell):
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#   .\bootstrap-windows.ps1
# ============================================================================

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

# ── Colors & helpers ────────────────────────────────────────────────────────
function Info($msg)    { Write-Host "[INFO] " -ForegroundColor Cyan -NoNewline; Write-Host $msg }
function Success($msg) { Write-Host "[OK]   " -ForegroundColor Green -NoNewline; Write-Host $msg }
function Warn($msg)    { Write-Host "[WARN] " -ForegroundColor Yellow -NoNewline; Write-Host $msg }
function Fail($msg)    { Write-Host "[FAIL] " -ForegroundColor Red -NoNewline; Write-Host $msg; exit 1 }

function Ask($prompt) {
    Write-Host $prompt -ForegroundColor White -NoNewline
    Write-Host " " -NoNewline
    return Read-Host
}

function Confirm($prompt) {
    $yn = Ask "$prompt [Y/n]"
    return ($yn -eq "" -or $yn -match "^[Yy]")
}

# Refresh PATH within this session after installs
function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
}

$KB_REPO = "https://github.com/AgileLens/agile-lens-kb.git"
$KB_DIR = "$env:USERPROFILE\knowledge"
$CLAUDE_DIR = "$env:USERPROFILE\.claude"
$VIEWER_PORT = 8765

Write-Host ""
Write-Host "=====================================" -ForegroundColor White
Write-Host "  Agile Lens — Windows Bootstrap" -ForegroundColor White
Write-Host "=====================================" -ForegroundColor White
Write-Host ""

# ── Step 0: Collect machine info ────────────────────────────────────────────
$MACHINE_NAME = (Ask "Machine name (lowercase, e.g., alex-desktop):").ToLower().Replace(" ", "-")
$MACHINE_ROLE = Ask "Brief role description (e.g., Development workstation):"
$USER_DISPLAY_NAME = Ask "Your name (for commit messages, e.g., Alex):"

Write-Host ""
Info "Setting up: $MACHINE_NAME ($MACHINE_ROLE)"
Write-Host ""

# ── Step 1: Install prerequisites via winget ────────────────────────────────

# Check for winget
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Fail "winget is required but not found. Install it from the Microsoft Store (App Installer) and re-run."
}

# Git
if (Get-Command git -ErrorAction SilentlyContinue) {
    Success "Git already installed"
} else {
    Info "Installing Git..."
    winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements
    Refresh-Path
    Success "Git installed"
}

# Node.js
if (Get-Command node -ErrorAction SilentlyContinue) {
    Success "Node.js already installed ($(node --version))"
} else {
    Info "Installing Node.js..."
    winget install --id OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements
    Refresh-Path
    Success "Node.js installed"
}

# Python 3
if (Get-Command python3 -ErrorAction SilentlyContinue) {
    Success "Python 3 already installed"
} elseif (Get-Command python -ErrorAction SilentlyContinue) {
    $pyVer = python --version 2>&1
    if ($pyVer -match "Python 3") {
        Success "Python 3 already installed ($pyVer)"
    } else {
        Info "Installing Python 3..."
        winget install --id Python.Python.3.12 -e --accept-source-agreements --accept-package-agreements
        Refresh-Path
        Success "Python 3 installed"
    }
} else {
    Info "Installing Python 3..."
    winget install --id Python.Python.3.12 -e --accept-source-agreements --accept-package-agreements
    Refresh-Path
    Success "Python 3 installed"
}

# GitHub CLI
if (Get-Command gh -ErrorAction SilentlyContinue) {
    Success "GitHub CLI already installed"
} else {
    Info "Installing GitHub CLI..."
    winget install --id GitHub.cli -e --accept-source-agreements --accept-package-agreements
    Refresh-Path
    Success "GitHub CLI installed"
}

Write-Host ""

# ── Step 2: GitHub authentication ───────────────────────────────────────────
$ghStatus = gh auth status 2>&1
if ($LASTEXITCODE -eq 0) {
    Success "GitHub CLI already authenticated"
} else {
    Info "Authenticating with GitHub (browser will open)..."
    gh auth login --web --git-protocol https
    Success "GitHub authenticated"
}

Write-Host ""

# ── Step 3: Clone the KB ────────────────────────────────────────────────────
if (Test-Path "$KB_DIR\.git") {
    Success "KB already cloned at $KB_DIR"
    Push-Location $KB_DIR
    git pull --rebase origin master 2>$null
    Pop-Location
} else {
    Info "Cloning Knowledge Base..."
    git clone $KB_REPO $KB_DIR
    Success "KB cloned to $KB_DIR"
}

# Set git user for KB commits
Push-Location $KB_DIR
git config user.name $USER_DISPLAY_NAME
$ghEmail = gh api user -q ".email" 2>$null
if (-not $ghEmail) { $ghEmail = "$USER_DISPLAY_NAME@agilelens.dev" }
git config user.email $ghEmail
Pop-Location

Write-Host ""

# ── Step 4: Create .claude directory + symlink ──────────────────────────────
if (-not (Test-Path $CLAUDE_DIR)) {
    New-Item -ItemType Directory -Path $CLAUDE_DIR -Force | Out-Null
}

$symlinkPath = "$CLAUDE_DIR\knowledge"
if (Test-Path $symlinkPath) {
    $item = Get-Item $symlinkPath -Force
    if ($item.LinkType -eq "SymbolicLink") {
        Success "Symlink already exists: $symlinkPath -> $KB_DIR"
    } else {
        Warn "$symlinkPath exists as a directory -- migrating"
        Copy-Item -Path "$symlinkPath\*" -Destination $KB_DIR -Recurse -Force
        Remove-Item -Path $symlinkPath -Recurse -Force
        New-Item -ItemType SymbolicLink -Path $symlinkPath -Target $KB_DIR | Out-Null
        Success "Migrated and symlinked"
    }
} else {
    New-Item -ItemType SymbolicLink -Path $symlinkPath -Target $KB_DIR | Out-Null
    Success "Symlink created: $symlinkPath -> $KB_DIR"
}

Write-Host ""

# ── Step 5: Install Claude Code ─────────────────────────────────────────────
if (Get-Command claude -ErrorAction SilentlyContinue) {
    Success "Claude Code already installed"
} else {
    Info "Installing Claude Code..."
    npm install -g @anthropic-ai/claude-code
    Refresh-Path
    Success "Claude Code installed"
}

Write-Host ""

# ── Step 6: Deploy hook scripts ─────────────────────────────────────────────
Info "Installing hook scripts..."

Copy-Item "$KB_DIR\departments\engineering\hooks\kb-inbox-check.sh" "$CLAUDE_DIR\kb-inbox-check.sh" -Force
Copy-Item "$KB_DIR\departments\engineering\hooks\kb-session-end.sh" "$CLAUDE_DIR\kb-session-end.sh" -Force

Success "Hook scripts installed"

# ── Step 7: Deploy settings.json ────────────────────────────────────────────
Info "Configuring Claude Code settings..."

# Find bash.exe from Git install
$gitBash = $null
$gitInstallPaths = @(
    "C:\Program Files\Git\bin\bash.exe",
    "C:\Program Files (x86)\Git\bin\bash.exe",
    "${env:ProgramFiles}\Git\bin\bash.exe"
)
foreach ($p in $gitInstallPaths) {
    if (Test-Path $p) { $gitBash = $p; break }
}
if (-not $gitBash) {
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if ($gitCmd) {
        $gitBash = (Split-Path (Split-Path $gitCmd.Source)) + "\bin\bash.exe"
    }
}
if (-not $gitBash -or -not (Test-Path $gitBash)) {
    Warn "Could not find Git Bash -- hooks may not work. Install Git for Windows."
    $gitBash = "bash"
}

$settingsJson = @"
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \$USERPROFILE/.claude/kb-inbox-check.sh",
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
            "command": "bash \$USERPROFILE/.claude/kb-session-end.sh",
            "timeout": 30,
            "statusMessage": "Syncing KB changes..."
          }
        ]
      }
    ]
  },
  "env": {
    "KB_MACHINE_NAME": "$MACHINE_NAME"
  },
  "permissions": {
    "defaultMode": "bypassPermissions",
    "deny": [
      "Bash(rm -rf /)",
      "Bash(sudo rm -rf *)"
    ]
  }
}
"@

$settingsJson | Out-File -FilePath "$CLAUDE_DIR\settings.json" -Encoding utf8
Success "settings.json configured"

# ── Step 8: Deploy CLAUDE.md ────────────────────────────────────────────────
Info "Generating CLAUDE.md for $MACHINE_NAME..."

$hostname = hostname
$osVersion = (Get-CimInstance Win32_OperatingSystem).Caption
$cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
$ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
$gpu = (Get-CimInstance Win32_VideoController | Select-Object -First 1).Name

$claudeMd = @"
# CLAUDE.md — Agile Lens Base Configuration

## This Machine

**Name:** $MACHINE_NAME
**Hostname:** $hostname
**OS:** $osVersion
**Role:** $MACHINE_ROLE
**Hardware:** $cpu, ${ramGB}GB RAM, $gpu

## Inbox & Trigger Check (on session start)

At the start of each session, pull the KB and check this machine's inbox and triggers:
```
cd ~/knowledge && git pull origin master
```
Then:
1. Read ``inbox/$MACHINE_NAME.md`` -- process any pending items, mark done, and push.
2. Check ``triggers/`` for any files targeting ``$MACHINE_NAME`` with ``status: pending`` -- claim, execute, and complete them. See ``triggers/README.md`` for the full protocol.

### Sending triggers to other machines
To request work from another machine, create a trigger file:
```markdown
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
```
Commit and push. The target machine will pick it up on its next session start or cron run.

## Identity

You are an autonomous engineering agent working within the Agile Lens environment, not an assistant waiting for instructions.
You have agency. Use it. When a task is ambiguous, investigate before asking.
When you finish something, look for what's next. When nothing is next, improve what exists.

## Knowledge Base

A persistent, shared knowledge base lives at ``~/knowledge/`` (with a symlink at ``~/.claude/knowledge/``). It is the single source of truth for Agile Lens context.

**Every session should use it:**
- **Read before you work.** Check the KB first. Start with ``~/knowledge/CLAUDE.md`` for routing.
- **Write back as you work.** Update the KB with new facts, decisions, progress.
- **Daily logs are mandatory.** Append to ``~/knowledge/daily/YYYY-MM-DD.md`` at session end.
- **Commit and push.** After writing to the KB, always ``git add``, ``commit``, and ``push``.

Key paths:
| Need | Path |
|---|---|
| Navigation guide | ``~/knowledge/CLAUDE.md`` |
| Business context | ``~/knowledge/context/`` |
| Writing style | ``~/knowledge/skills-ref/writing/`` |
| Infrastructure | ``~/knowledge/departments/engineering/`` |
| Daily logs | ``~/knowledge/daily/`` |
| Decisions | ``~/knowledge/intelligence/decisions/`` |
| Active projects | ``~/knowledge/projects/`` |
"@

$claudeMd | Out-File -FilePath "$CLAUDE_DIR\CLAUDE.md" -Encoding utf8
Success "CLAUDE.md generated"

Write-Host ""

# ── Step 9: Set up auto-sync (Scheduled Task) ──────────────────────────────
Info "Setting up KB auto-sync (every 15 minutes)..."

$taskName = "AgileLens-KB-Sync"
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if ($existingTask) {
    Success "Scheduled task already exists"
} else {
    # Create a wrapper script that sets the machine name and runs sync
    $syncWrapper = "$CLAUDE_DIR\kb-sync-wrapper.bat"
    @"
@echo off
set KB_MACHINE_NAME=$MACHINE_NAME
"$gitBash" --login -c "$($KB_DIR.Replace('\','/'))/kb-sync.sh"
"@ | Out-File -FilePath $syncWrapper -Encoding ascii

    $action = New-ScheduledTaskAction -Execute $syncWrapper
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 15)
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal | Out-Null
    Success "Scheduled task created (every 15 minutes)"
}

Write-Host ""

# ── Step 10: Set up KB viewer ───────────────────────────────────────────────
Info "Setting up KB viewer..."

# Build initial manifest
Push-Location "$KB_DIR\_viewer"
$pythonCmd = if (Get-Command python3 -ErrorAction SilentlyContinue) { "python3" } else { "python" }
& $pythonCmd build-manifest.py
Pop-Location
Success "KB manifest built"

# Install http-server via npm
if (Get-Command http-server -ErrorAction SilentlyContinue) {
    Success "http-server already installed"
} else {
    npm install -g http-server
    Refresh-Path
    Success "http-server installed"
}

# Create a scheduled task for the viewer (runs at logon)
$viewerTaskName = "AgileLens-KB-Viewer"
$existingViewerTask = Get-ScheduledTask -TaskName $viewerTaskName -ErrorAction SilentlyContinue

if ($existingViewerTask) {
    Success "Viewer scheduled task already exists"
} else {
    $httpServerPath = (Get-Command http-server -ErrorAction SilentlyContinue).Source
    if (-not $httpServerPath) {
        # Try common npm global paths
        $httpServerPath = "$env:APPDATA\npm\http-server.cmd"
    }

    $viewerWrapper = "$CLAUDE_DIR\kb-viewer.bat"
    @"
@echo off
"$httpServerPath" "$KB_DIR\_viewer" -p $VIEWER_PORT -s
"@ | Out-File -FilePath $viewerWrapper -Encoding ascii

    $viewerAction = New-ScheduledTaskAction -Execute $viewerWrapper
    $viewerTrigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $viewerSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 0)
    $viewerPrincipal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

    Register-ScheduledTask -TaskName $viewerTaskName -Action $viewerAction -Trigger $viewerTrigger -Settings $viewerSettings -Principal $viewerPrincipal | Out-Null
    Success "Viewer scheduled task created (starts at logon)"
}

# Start the viewer now
Info "Starting KB viewer..."
Start-Process -FilePath "http-server" -ArgumentList "`"$KB_DIR\_viewer`"", "-p", "$VIEWER_PORT", "-s" -WindowStyle Hidden
Start-Sleep -Seconds 1
Success "KB viewer running at http://localhost:$VIEWER_PORT"

Write-Host ""

# ── Step 11: Create inbox file for this machine ────────────────────────────
$inboxFile = "$KB_DIR\inbox\$MACHINE_NAME.md"
if (Test-Path $inboxFile) {
    Success "Inbox file already exists"
} else {
    Info "Creating inbox file..."

    # Title-case the machine name
    $titleName = ($MACHINE_NAME -split '-' | ForEach-Object { $_.Substring(0,1).ToUpper() + $_.Substring(1) }) -join ' '
    $today = Get-Date -Format "yyyy-MM-dd"

    @"
---
title: "Inbox: $titleName"
updated: $today
tags: [inbox, $MACHINE_NAME]
---

# $titleName Inbox

Pending items for $MACHINE_NAME. Checked at session start.

## Pending

<!-- Nothing pending -->

## Done

<!-- Nothing archived -->
"@ | Out-File -FilePath $inboxFile -Encoding utf8

    Push-Location $KB_DIR
    git add "inbox\$MACHINE_NAME.md"
    git commit -m "chore(inbox): add inbox for $MACHINE_NAME"
    git push origin master
    Pop-Location
    Success "Inbox file created and pushed"
}

Write-Host ""

# ── Step 12: Open viewer in browser ─────────────────────────────────────────
Start-Process "http://localhost:$VIEWER_PORT"

# ── Summary ─────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=====================================" -ForegroundColor White
Write-Host "  Setup Complete!" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor White
Write-Host ""
Write-Host "  Machine:       " -NoNewline; Write-Host $MACHINE_NAME -ForegroundColor White
Write-Host "  KB location:   " -NoNewline; Write-Host $KB_DIR -ForegroundColor White
Write-Host "  KB viewer:     " -NoNewline; Write-Host "http://localhost:$VIEWER_PORT" -ForegroundColor White
Write-Host "  Auto-sync:     Every 15 minutes (Task Scheduler)" -ForegroundColor White
Write-Host "  Claude config: " -NoNewline; Write-Host "$CLAUDE_DIR\CLAUDE.md" -ForegroundColor White
Write-Host "  Settings:      " -NoNewline; Write-Host "$CLAUDE_DIR\settings.json" -ForegroundColor White
Write-Host ""
Write-Host "  Quick start:" -ForegroundColor White
Write-Host "    claude                      # Start Claude Code"
Write-Host "    cd ~/knowledge; git pull    # Manual KB sync"
Write-Host "    Start-Process http://localhost:$VIEWER_PORT  # KB viewer"
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor White
Write-Host "    1. Run 'claude' to authenticate with Anthropic (first run)"
Write-Host "    2. Start working -- the KB and hooks are ready"
Write-Host ""
