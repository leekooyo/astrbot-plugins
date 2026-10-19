# RepoWatch

RepoWatch is a short-lived PowerShell checker for multiple Git repositories and optional deployment folders. It is designed for periodic Task Scheduler runs, including machines where agent tools do not expose a task-completion hook.

## What it checks

- Uncommitted and untracked files in each configured repository.
- Local `HEAD` against the local remote-tracking branch, plus a read-only `git ls-remote` check against the current remote branch. It does not fetch, commit, push, merge, or change branches.
- SHA-256 differences between Git-tracked source/document files and deployment files. It also counts eligible deployment files that have no tracked counterpart, which catches newly added runtime files.
- Emails only when a repository has local changes that may need to reach GitHub: an uncommitted working tree, local commits ahead of the recorded remote branch, or differences in the AstrBot runtime folder. Remote-only changes, check failures, and recovery do not send mail. Each email lists every currently pending repository with plain-language reasons and next steps. A new or changed pending difference triggers one email; unchanged differences do not repeat hourly. If delivery fails, notification state is not advanced, so the next run retries. The local JSON state stores hashes, not file contents.

The checker reads eligible files to hash them. It never reads or sends their contents. Excluded path segments include `.git`, `__pycache__`, test directories, `UPSTREAM.md`, `node_modules`, virtual environments, caches, logs, temporary files, and runtime `data` directories. `excludeRuntimePaths` handles intentional machine-local files such as `image_host/config.json`. The extension allowlist and exclusions are configurable.

## Setup

1. Copy `config.example.json` to a private local path, such as `%LOCALAPPDATA%\RepoWatch\config.json`.
2. Replace every `REPLACE_WITH_LOCAL_PATH` with the parent folder containing the Git checkouts and `REPLACE_WITH_ASTRBOT_PLUGIN_PATH` with the AstrBot plugin directory. Edit `statePath` to an absolute local path. Set the SMTP server, username, sender, recipient, and TLS port in the local config. Keep this machine-specific file out of Git.
3. Enable SMTP service with the mailbox provider and create an app password or authorization code. For QQ Mail, the server is `smtp.qq.com`; port `587` uses STARTTLS. Use the mailbox's authorization code rather than its normal login password. RepoWatch prompts for the code with hidden input and stores it encrypted with Windows DPAPI for the current Windows user.
4. Run the one-time installer from a Windows PowerShell 5.1 window as your normal user:

   ```powershell
   .\Install-RepoWatchTask.ps1 -ConfigPath "$env:LOCALAPPDATA\RepoWatch\config.json"
   ```

   It copies the watcher, notification helper, and email initializer next to the local config, then creates `RepoWatch-Hourly` using those durable local copies. The task runs only in your interactive login session, starts within two minutes, and repeats hourly. It requires no administrator rights. Rerun the installer after updating the repository scripts to refresh the installed copies.
5. Initialize email from the installed local copy. This prompts for the authorization code without echoing it and saves it encrypted. It sends an email only if repositories currently need attention:

   ```powershell
   & "$env:LOCALAPPDATA\RepoWatch\Initialize-RepoWatchEmail.ps1" -ConfigPath "$env:LOCALAPPDATA\RepoWatch\config.json"
   ```

6. Run a silent local check without sending mail. This does not mark pending changes as already emailed:

   ```powershell
   .\Watch-Repos.ps1 -ConfigPath "$env:LOCALAPPDATA\RepoWatch\config.json" -NoNotify
   ```

7. To remove the task, run `.\Install-RepoWatchTask.ps1 -ConfigPath <config> -Uninstall`.

## Status meanings

`working-tree` means local edits, staged changes, or untracked files exist. `local-ahead` means local commits are not in the configured tracking branch; it is removed when the live remote tip matches local `HEAD`. `tracking-behind` means the local tracking ref contains commits not in `HEAD`. `remote-ref-changed` means GitHub's current branch tip differs from the last locally fetched tracking ref; a manual fetch is needed to calculate exact divergence. `deployment-drift` means tracked files and the configured runtime directory differ. Network/authentication problems are summarized as `remote-check-failed` and can resolve on the next run.

Remote checks use the Git credentials already configured for that checkout. Ensure GitHub credentials are available to your normal Windows user. The checker never prints remote URLs or raw Git errors.

SMTP credentials are never placed in the example config or repository. The encrypted DPAPI file can only be decrypted by the same Windows user on the same computer. Use a separate authorization code per machine if you reuse RepoWatch elsewhere.

`proxyMode` defaults to `git-config`, which respects each user's Git proxy settings. Set it to `direct` only when GitHub is reachable without the configured proxy; RepoWatch then overrides proxy settings for its read-only remote query without changing Git configuration.

## Reuse

Copy this folder into another checkout and create a separate local config for each machine. Set any `repoPath`, optional `deployPath`, remote name, and branch. Config files may contain personal filesystem paths and should remain local.
