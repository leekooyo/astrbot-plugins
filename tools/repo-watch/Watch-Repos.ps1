[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,
    [switch]$NoNotify
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'RepoWatch.Notifications.ps1')

function Get-GitOutput {
    param([string]$Repository, [string[]]$GitArgs, [string]$ProxyMode = 'git-config')
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    if ($ProxyMode -eq 'direct') {
        $result = @(& git -c http.proxy= -c https.proxy= -C $Repository @GitArgs 2>$null)
    } else {
        $result = @(& git -C $Repository @GitArgs 2>$null)
    }
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousPreference
    [pscustomobject]@{ ExitCode = $exitCode; Lines = $result }
}

function Get-ContentFingerprint {
    param([string[]]$Parts)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes(($Parts -join "`n"))
        ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-DeploySummary {
    param($RepositoryConfig, $MonitorConfig)
    if (-not $RepositoryConfig.PSObject.Properties['deployPath'] -or -not $RepositoryConfig.deployPath) { return $null }

    $tracked = Get-GitOutput -Repository $RepositoryConfig.repoPath -GitArgs @('-c', 'core.quotepath=false', 'ls-files')
    if ($tracked.ExitCode -ne 0) { throw 'Unable to list tracked files.' }
    $extensions = @($MonitorConfig.deployExtensions | ForEach-Object { $_.ToLowerInvariant() })
    $excluded = @($MonitorConfig.excludeDeployPaths | ForEach-Object { $_.Replace('\', '/').Trim('/').ToLowerInvariant() })
    $excludedRuntimePaths = @()
    if ($MonitorConfig.PSObject.Properties['excludeRuntimePaths']) {
        $excludedRuntimePaths = @($MonitorConfig.excludeRuntimePaths | ForEach-Object { $_.Replace('\', '/').Trim('/').ToLowerInvariant() })
    }

    $expected = @{}
    foreach ($relative in $tracked.Lines) {
        if ([string]::IsNullOrWhiteSpace($relative)) { continue }
        $normalized = $relative.Replace('\', '/')
        $extension = [IO.Path]::GetExtension($normalized).ToLowerInvariant()
        if ($extensions.Count -gt 0 -and $extension -notin $extensions) { continue }
        if (@($normalized.Split('/') | Where-Object { $_.ToLowerInvariant() -in $excluded }).Count -gt 0) { continue }
        $lowerRelative = $normalized.ToLowerInvariant()
        if (@($excludedRuntimePaths | Where-Object { $lowerRelative -eq $_ -or $lowerRelative.StartsWith($_ + '/') }).Count -gt 0) { continue }
        $expected[$normalized] = $true
    }

    $different = 0
    $missing = 0
    $differences = [Collections.Generic.List[string]]::new()
    foreach ($relative in $expected.Keys) {
        $deployFile = Join-Path $RepositoryConfig.deployPath ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
        if (-not (Test-Path -LiteralPath $deployFile -PathType Leaf)) { $missing++; $differences.Add("missing:$relative"); continue }
        $sourceFile = Join-Path $RepositoryConfig.repoPath ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
        $sourceHash = (Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256).Hash
        $deployHash = (Get-FileHash -LiteralPath $deployFile -Algorithm SHA256).Hash
        if ($sourceHash -ne $deployHash) { $different++; $differences.Add("different:$relative`:$sourceHash`:$deployHash") }
    }

    $unexpected = 0
    if (Test-Path -LiteralPath $RepositoryConfig.deployPath -PathType Container) {
        $trackedSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($relative in $expected.Keys) { [void]$trackedSet.Add($relative.Replace('/', '\')) }
        foreach ($file in Get-ChildItem -LiteralPath $RepositoryConfig.deployPath -File -Recurse -ErrorAction SilentlyContinue) {
            $deployRoot = [IO.Path]::GetFullPath($RepositoryConfig.deployPath).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
            $relative = $file.FullName.Substring($deployRoot.Length)
            $extension = [IO.Path]::GetExtension($relative).ToLowerInvariant()
            if ($extensions.Count -gt 0 -and $extension -notin $extensions) { continue }
            $normalized = $relative.Replace('\', '/')
            if (@($normalized.Split('/') | Where-Object { $_.ToLowerInvariant() -in $excluded }).Count -gt 0) { continue }
            $lowerRelative = $normalized.ToLowerInvariant()
            if (@($excludedRuntimePaths | Where-Object { $lowerRelative -eq $_ -or $lowerRelative.StartsWith($_ + '/') }).Count -gt 0) { continue }
            if (-not $trackedSet.Contains($relative)) {
                $unexpected++
                $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
                $differences.Add("unexpected:$normalized`:$hash")
            }
        }
    }
    [pscustomobject]@{ Different = $different; Missing = $missing; Unexpected = $unexpected; Fingerprint = Get-ContentFingerprint -Parts @($differences | Sort-Object) }
}

function Get-RepoStatus {
    param($RepositoryConfig, $MonitorConfig)
    $repo = [IO.Path]::GetFullPath($RepositoryConfig.repoPath)
    if (-not (Test-Path -LiteralPath (Join-Path $repo '.git'))) { throw 'Repository path is not a Git working tree.' }

    $issues = [Collections.Generic.List[string]]::new()
    $status = Get-GitOutput -Repository $repo -GitArgs @('status', '--porcelain=v1', '--untracked-files=normal')
    if ($status.ExitCode -ne 0) { throw 'Unable to inspect Git working tree.' }
    if ($status.Lines.Count -gt 0) { $issues.Add('working-tree') }
    $fingerprintParts = [Collections.Generic.List[string]]::new()
    if ($status.Lines.Count -gt 0) {
        $changedFiles = Get-GitOutput -Repository $repo -GitArgs @('-c', 'core.quotepath=false', 'ls-files', '-m', '-d', '-o', '--exclude-standard')
        if ($changedFiles.ExitCode -ne 0) { throw 'Unable to inspect changed files.' }
        foreach ($relative in @($changedFiles.Lines | Sort-Object -Unique)) {
            $file = Join-Path $repo ([string]$relative)
            $hash = if (Test-Path -LiteralPath $file -PathType Leaf) { (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash } else { 'missing' }
            $fingerprintParts.Add("working:$relative`:$hash")
        }
        foreach ($line in $status.Lines) { $fingerprintParts.Add("status:$line") }
    }

    $branch = [string]$RepositoryConfig.branch
    $remote = [string]$RepositoryConfig.remote
    if ($branch -notmatch '^[A-Za-z0-9._/-]+$' -or $remote -notmatch '^[A-Za-z0-9._-]+$') { throw 'Invalid remote or branch in configuration.' }
    $trackingRef = "refs/remotes/$remote/$branch"
    $head = Get-GitOutput -Repository $repo -GitArgs @('rev-parse', 'HEAD')
    if ($head.ExitCode -ne 0) { throw 'Unable to inspect HEAD.' }
    $headHash = [string]$head.Lines[0]
    $tracking = Get-GitOutput -Repository $repo -GitArgs @('rev-parse', '--verify', $trackingRef)
    if ($tracking.ExitCode -eq 0) {
        $divergence = Get-GitOutput -Repository $repo -GitArgs @('rev-list', '--left-right', '--count', "HEAD...$trackingRef")
        if ($divergence.ExitCode -eq 0 -and $divergence.Lines.Count -gt 0) {
            $parts = ([string]$divergence.Lines[0]).Trim() -split '\s+'
            if ([int]$parts[0] -gt 0) { $issues.Add('local-ahead') }
            if ([int]$parts[1] -gt 0) { $issues.Add('tracking-behind') }
        }
    } else {
        $issues.Add('tracking-ref-missing')
    }

    $proxyMode = if ($MonitorConfig.PSObject.Properties['proxyMode']) { [string]$MonitorConfig.proxyMode } else { 'git-config' }
    if ($proxyMode -notin @('git-config', 'direct')) { throw 'proxyMode must be git-config or direct.' }
    $remoteResult = Get-GitOutput -Repository $repo -GitArgs @('ls-remote', '--heads', $remote, "refs/heads/$branch") -ProxyMode $proxyMode
    if ($remoteResult.ExitCode -ne 0) {
        $issues.Add('remote-check-failed')
    } else {
        $remoteLine = @($remoteResult.Lines | Where-Object { $_ }) | Select-Object -First 1
        if (-not $remoteLine) {
            $issues.Add('remote-branch-missing')
        } elseif ($tracking.ExitCode -eq 0) {
            $remoteHash = ([string]$remoteLine -split '\s+')[0]
            $trackingHash = [string](Get-GitOutput -Repository $repo -GitArgs @('rev-parse', $trackingRef)).Lines[0]
            if ($remoteHash -ne $trackingHash) { $issues.Add('remote-ref-changed') }
            if ($remoteHash -eq $headHash) { [void]$issues.Remove('local-ahead') }
        } else {
            $issues.Add('remote-ref-changed')
        }
    }

    $deploy = Get-DeploySummary -RepositoryConfig $RepositoryConfig -MonitorConfig $MonitorConfig
    if ($deploy -and ($deploy.Different -gt 0 -or $deploy.Missing -gt 0 -or $deploy.Unexpected -gt 0)) { $issues.Add('deployment-drift') }
    if ($issues.Contains('local-ahead')) { $fingerprintParts.Add("head:$headHash") }
    if ($issues.Contains('deployment-drift')) { $fingerprintParts.Add("deploy:$($deploy.Fingerprint)") }
    [pscustomobject]@{ Name = [string]$RepositoryConfig.name; Issues = @($issues | Sort-Object -Unique); Deploy = $deploy; Fingerprint = Get-ContentFingerprint -Parts @($fingerprintParts | Sort-Object) }
}

$configFile = (Resolve-Path -LiteralPath $ConfigPath).Path
$config = Get-Content -LiteralPath $configFile -Raw | ConvertFrom-Json
if (-not $config.repositories -or -not $config.statePath) { throw 'Configuration must contain repositories and statePath.' }
$statePath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$config.statePath))
$notifiedSignatures = @{}
if (Test-Path -LiteralPath $statePath) {
    try {
        $parsed = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        if ($parsed.PSObject.Properties['notifiedSignatures']) {
            foreach ($property in $parsed.notifiedSignatures.PSObject.Properties) { $notifiedSignatures[[string]$property.Name] = [string]$property.Value }
        }
    } catch { $notifiedSignatures = @{} }
}

$newResults = [Collections.Generic.List[object]]::new()
foreach ($repository in $config.repositories) {
    try {
        $result = Get-RepoStatus -RepositoryConfig $repository -MonitorConfig $config
        $newResults.Add($result)
        $newIssues = @($result.Issues | Sort-Object -Unique)
        $deployDetails = if ($result.Deploy) { "; deployment diff=$($result.Deploy.Different), missing=$($result.Deploy.Missing), extra=$($result.Deploy.Unexpected)" } else { '' }
        Write-Output ("{0}: {1}{2}" -f $repository.name, $(if ($newIssues.Count) { $newIssues -join ', ' } else { 'OK' }), $deployDetails)
    } catch {
        $failed = [pscustomobject]@{ Name = [string]$repository.name; Issues = @('check-failed'); Deploy = $null; Fingerprint = '' }
        $newResults.Add($failed)
        Write-Verbose ("{0}: line {1}: check failed: {2}" -f $repository.name, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message)
        Write-Output ("{0}: CHECK FAILED" -f $repository.name)
    }
}

$notification = Get-RepoWatchNotification -Results $newResults.ToArray() -PreviousSignaturesByName $notifiedSignatures
if (-not $NoNotify -and $notification.ShouldSend) {
    if (-not $config.PSObject.Properties['smtp']) { throw 'SMTP settings are missing from the local configuration.' }
    try {
        Send-RepoWatchEmail -Smtp $config.smtp -Subject $notification.Subject -Body $notification.Body
        $notifiedSignatures = $notification.SignaturesByName
        Write-Output 'Email notification sent.'
    } catch {
        throw 'Unable to send RepoWatch email. Notification state was not saved and will be retried on the next run.'
    }
}
if (-not $NoNotify -and -not $notification.ShouldSend) { $notifiedSignatures = $notification.SignaturesByName }

$orderedSignatures = [ordered]@{}
foreach ($name in @($notifiedSignatures.Keys | Sort-Object)) { $orderedSignatures[$name] = [string]$notifiedSignatures[$name] }
$newState = [pscustomobject]@{ version = 4; notifiedSignatures = $orderedSignatures; repositories = @($newResults | ForEach-Object { [pscustomobject]@{ name = $_.Name; issues = @($_.Issues); fingerprint = [string]$_.Fingerprint } }) }
$stateJson = $newState | ConvertTo-Json -Depth 5
$writeState = $true
if (Test-Path -LiteralPath $statePath) {
    try { $oldJson = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json | ConvertTo-Json -Depth 5; if ($oldJson -eq $stateJson) { $writeState = $false } } catch { }
}
if ($writeState) {
    $stateDirectory = Split-Path -Parent $statePath
    New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
    $stateJson | Set-Content -LiteralPath $statePath -Encoding UTF8
}
