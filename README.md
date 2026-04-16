# Agile Lens — Machine Setup

Bootstrap scripts for setting up a new Agile Lens team member's Mac or Windows machine with Claude Code, the shared Knowledge Base, auto-sync, and all hooks.

## What it does

Running the bootstrap script on a fresh machine:
- Installs Claude Code and required CLI tools
- Clones the shared Agile Lens Knowledge Base to `~/knowledge`
- Configures auto-sync hooks so KB changes push automatically
- Registers the machine in the fleet roster
- Sets up the KB viewer on a local port

## Quick Start

**macOS:**
```bash
bash bootstrap-mac.sh
```

**Windows:**
```powershell
.\bootstrap-windows.ps1
```

Both scripts are interactive — they'll ask for machine name, role, and your display name.

## Things to Try

1. **Run `bash bootstrap-mac.sh` on a fresh Mac and answer the prompts** — the script installs Claude Code, clones the KB, and configures hooks; when it finishes, `~/knowledge` should exist and `git status` should show a clean repo.
2. **Open a new terminal after the bootstrap and run `claude`** — Claude Code launches with the shared KB already in context; ask "what is my machine's role?" and it should answer from the fleet roster.
3. **Make a small edit to any file in `~/knowledge` and save** — the post-save hook should auto-commit and push to the KB repo within a few seconds; verify with `git log --oneline ~/knowledge`.
4. **Run the bootstrap a second time on the same machine** — it should detect existing installations and skip or update them cleanly, not duplicate any configuration.
5. **Run `bootstrap-windows.ps1` on a Windows machine** — same end state as macOS; Claude Code installed, KB cloned, hooks active.

## Files

| File | Purpose |
|------|---------|
| `bootstrap-mac.sh` | macOS setup script (bash) |
| `bootstrap-windows.ps1` | Windows setup script (PowerShell) |
