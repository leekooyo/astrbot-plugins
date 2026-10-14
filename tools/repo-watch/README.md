# RepoWatch

RepoWatch is a short-lived PowerShell checker for multiple Git repositories and optional deployment folders. It is designed for periodic Task Scheduler runs, including machines where agent tools do not expose a task-completion hook.

## What it checks

- Uncommitted and untracked files in each configured repository.
- Local `HEAD` against the local remote-tracking branch, plus a read-only `git ls-remote` check against the current remote branch. It does not fetch, commit, push, merge, or change branches.
- SHA-256 differences between Git-tracked source/document files and deployment files. It also counts eligible deployment files that have no tracked counterpart, which catches newly added runtime files.
- Notifications only when a repository's issue categories change, and one recovery notice when it becomes clean. State is written to a local JSON file only when it changes.

The checker reads eligible files to hash them. It never reads or sends their contents. Excluded path segments include `.git`, `__pycache__`, test directories, `UPSTREAM.md`, `node_modules`, virtual environments, caches, logs, temporary files, and runtime `data` directories. `excludeRuntimePaths` handles intentional machine-local files such as `image_host/config.json`. The extension allowlist and exclusions are configurable.

## Setup

1. Copy `config.example.json` to a private local path, such as `%LOCALAPPDATA%\RepoWatch\config.json`.
2. Replace every `REPLACE_WITH_LOCAL_PATH` with the parent folder containing the Git checkouts and `REPLACE_WITH_ASTRBOT_PLUGIN_PATH` with the AstrBot plugin directory. Edit `statePath` to an absolute local path. Keep this machine-specific file out of Git.
3. Run the one-time installer from a PowerShell window as your normal user:

   ```powershell
   .\Install-RepoWatchTask.ps1 -ConfigPath "$env:LOCALAPPDATA\RepoWatch\config.json"
   ```

   Run it from Windows PowerShell 5.1. It creates `RepoWatch-Hourly`. The task runs only in your interactive login session, starts within two minutes, and repeats hourly. It requires no administrator rights.
4. Test a run manually:

   ```powershell
   .\Watch-Repos.ps1 -ConfigPath "$env:LOCALAPPDATA\RepoWatch\config.json" -NoNotify
   ```

5. To remove the task, run `.Install-RepoWatchTask.ps1 -ConfigPath <config> -Uninstall`.

## Status meanings

`working-tree` means local edits, staged changes, or untracked files exist. `local-ahead` means local commits are not in the configured tracking branch. `tracking-behind` means the local tracking ref contains commits not in `HEAD`. `remote-ref-changed` means GitHub's current branch tip differs from the last locally fetched tracking ref; a manual fetch is needed to calculate exact divergence. `deployment-drift` means tracked files and the configured runtime directory differ. Network/authentication problems are summarized as `remote-check-failed` and can resolve on the next run.

Remote checks use the Git credentials already configured for that checkout. Ensure GitHub credentials are available to your normal Windows user. The checker never prints remote URLs or raw Git errors.

`proxyMode` defaults to `git-config`, which respects each user's Git proxy settings. Set it to `direct` only when GitHub is reachable without the configured proxy; RepoWatch then overrides proxy settings for its read-only remote query without changing Git configuration.

## Reuse

Copy this folder into another checkout and create a separate local config for each machine. Set any `repoPath`, optional `deployPath`, remote name, and branch. Config files may contain personal filesystem paths and should remain local.
