$ErrorActionPreference = 'Stop'

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('repowatch-fingerprint-' + [guid]::NewGuid().ToString('N'))
$repo = Join-Path $tempRoot 'repo'
$remote = Join-Path $tempRoot 'remote.git'
$deploy = Join-Path $tempRoot 'deploy'
$configPath = Join-Path $tempRoot 'config.json'
$statePath = Join-Path $tempRoot 'state.json'
$watcher = Join-Path $PSScriptRoot '..\Watch-Repos.ps1'

try {
    New-Item -ItemType Directory -Path $repo, $deploy -Force | Out-Null
    & git init -q $repo
    & git -C $repo branch -M main
    'initial' | Set-Content -LiteralPath (Join-Path $repo 'plugin.py') -Encoding UTF8
    & git -C $repo add plugin.py
    & git -C $repo -c user.name=RepoWatchTest -c user.email=test@example.invalid commit -qm initial
    & git init --bare -q $remote
    & git -C $repo remote add origin $remote
    & git -C $repo push -q -u origin main
    Copy-Item -LiteralPath (Join-Path $repo 'plugin.py') -Destination (Join-Path $deploy 'plugin.py')

    $config = [pscustomobject]@{
        statePath = $statePath
        proxyMode = 'git-config'
        deployExtensions = @('.py')
        excludeDeployPaths = @()
        excludeRuntimePaths = @()
        repositories = @([pscustomobject]@{ name = 'test-plugin'; repoPath = $repo; deployPath = $deploy; branch = 'main'; remote = 'origin' })
    }
    $config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $configPath -Encoding UTF8

    & $watcher -ConfigPath $configPath -NoNotify | Out-Null
    $clean = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if (@($clean.repositories[0].issues).Count -ne 0) { throw 'Clean fixture unexpectedly has issues.' }

    'first runtime edit' | Set-Content -LiteralPath (Join-Path $deploy 'plugin.py') -Encoding UTF8
    & $watcher -ConfigPath $configPath -NoNotify | Out-Null
    $first = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if (@($first.repositories[0].issues) -notcontains 'deployment-drift') { throw 'Runtime edit was not detected.' }

    'second runtime edit' | Set-Content -LiteralPath (Join-Path $deploy 'plugin.py') -Encoding UTF8
    & $watcher -ConfigPath $configPath -NoNotify | Out-Null
    $second = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if (@($second.repositories[0].issues) -notcontains 'deployment-drift') { throw 'Persistent drift disappeared unexpectedly.' }
    if ($first.repositories[0].fingerprint -eq $second.repositories[0].fingerprint) { throw 'Runtime content change did not change the fingerprint.' }

    & $watcher -ConfigPath $configPath -NoNotify | Out-Null
    $stable = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if ($second.repositories[0].fingerprint -ne $stable.repositories[0].fingerprint) { throw 'Unchanged runtime content changed the fingerprint.' }
} finally {
    if ($tempRoot.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Output 'RepoWatch fingerprint tests passed.'
