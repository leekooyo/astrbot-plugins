$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot '..\RepoWatch.Notifications.ps1'
. $modulePath

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$current = @(
    [pscustomobject]@{ Name = 'plugin-a'; Issues = @('deployment-drift'); Deploy = [pscustomobject]@{ Different = 2; Missing = 0; Unexpected = 1 }; Fingerprint = 'runtime-a' },
    [pscustomobject]@{ Name = 'plugin-b'; Issues = @('working-tree'); Deploy = $null; Fingerprint = 'work-b' },
    [pscustomobject]@{ Name = 'plugin-c'; Issues = @('remote-ref-changed'); Deploy = $null; Fingerprint = 'remote-c' },
    [pscustomobject]@{ Name = 'plugin-d'; Issues = @(); Deploy = $null; Fingerprint = '' }
)

$initial = Get-RepoWatchNotification -Results $current -PreviousSignaturesByName @{}
Assert-True $initial.ShouldSend 'Pending local changes must send an email.'
Assert-True ($initial.Subject -match '2 个仓库') 'Subject must show the pending repository count.'
Assert-True ($initial.Body -match 'plugin-a') 'Email must list runtime differences.'
Assert-True ($initial.Body -match 'plugin-b') 'Email must list working-tree changes.'
Assert-True ($initial.Body -notmatch 'plugin-c|plugin-d') 'Email must omit remote-only and clean repositories.'
Assert-True ($initial.Body -match '核对|同步') 'Email must give an actionable next step.'

$unchanged = Get-RepoWatchNotification -Results $current -PreviousSignaturesByName $initial.SignaturesByName
Assert-True (-not $unchanged.ShouldSend) 'Unchanged pending changes must not send another email.'

$remoteChangedWithPending = Get-RepoWatchNotification -Results @(
    $current[0], $current[1],
    [pscustomobject]@{ Name = 'plugin-c'; Issues = @('remote-ref-changed'); Deploy = $null; Fingerprint = 'remote-new' },
    $current[3]
) -PreviousSignaturesByName $initial.SignaturesByName
Assert-True (-not $remoteChangedWithPending.ShouldSend) 'A remote-only change must not resend existing local differences.'

$contentChanged = @(
    [pscustomobject]@{ Name = 'plugin-a'; Issues = @('deployment-drift'); Deploy = $current[0].Deploy; Fingerprint = 'runtime-a-new' },
    $current[1], $current[2], $current[3]
)
$updated = Get-RepoWatchNotification -Results $contentChanged -PreviousSignaturesByName $initial.SignaturesByName
Assert-True $updated.ShouldSend 'Changed runtime contents must notify while drift remains active.'
Assert-True ($updated.Body -match 'plugin-a') 'Changed repository must be listed.'
Assert-True ($updated.Body -match 'plugin-b') 'Email must still list all currently pending repositories.'

$remoteOnly = Get-RepoWatchNotification -Results @(
    [pscustomobject]@{ Name = 'plugin-c'; Issues = @('remote-ref-changed', 'tracking-behind'); Deploy = $null; Fingerprint = 'remote-new' },
    [pscustomobject]@{ Name = 'plugin-e'; Issues = @('check-failed'); Deploy = $null; Fingerprint = '' }
) -PreviousSignaturesByName $initial.SignaturesByName
Assert-True (-not $remoteOnly.ShouldSend) 'Remote-only changes and check failures must not send email.'
Assert-True ($remoteOnly.SignaturesByName.Count -eq 0) 'No pending changes must clear notification signatures.'

$reappeared = Get-RepoWatchNotification -Results $current -PreviousSignaturesByName $remoteOnly.SignaturesByName
Assert-True $reappeared.ShouldSend 'A pending difference that reappears after recovery must notify.'

$failedWhilePending = Get-RepoWatchNotification -Results @(
    [pscustomobject]@{ Name = 'plugin-a'; Issues = @('check-failed'); Deploy = $null; Fingerprint = '' },
    $current[1]
) -PreviousSignaturesByName $initial.SignaturesByName
Assert-True (-not $failedWhilePending.ShouldSend) 'A check failure must not cause a false pending-change email.'
Assert-True ($failedWhilePending.SignaturesByName['plugin-a'] -eq $initial.SignaturesByName['plugin-a']) 'A failed check must preserve its last notified state.'

$tempCredentialPath = Join-Path ([IO.Path]::GetTempPath()) ('repowatch-test-' + [guid]::NewGuid().ToString('N') + '.dpapi')
try {
    $secure = ConvertTo-SecureString 'test-only-password' -AsPlainText -Force
    Save-RepoWatchCredential -CredentialPath $tempCredentialPath -SecurePassword $secure
    $roundTrip = Read-RepoWatchPassword -CredentialPath $tempCredentialPath
    Assert-True ($roundTrip -ceq 'test-only-password') 'DPAPI credential must round-trip for the current Windows user.'
} finally {
    Remove-Item -LiteralPath $tempCredentialPath -Force -ErrorAction SilentlyContinue
}

Write-Output 'RepoWatch notification tests passed.'
