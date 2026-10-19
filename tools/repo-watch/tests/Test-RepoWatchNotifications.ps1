$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot '..\RepoWatch.Notifications.ps1'
. $modulePath

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$current = @(
    [pscustomobject]@{ Name = 'plugin-a'; Issues = @('deployment-drift'); Deploy = $null },
    [pscustomobject]@{ Name = 'plugin-b'; Issues = @(); Deploy = $null }
)

$initial = Get-RepoWatchNotification -Results $current -PreviousIssuesByName @{} -IsInitial $true
Assert-True $initial.ShouldSend 'First run must send a current-state report.'
Assert-True ($initial.Body -match 'plugin-a.*deployment-drift') 'Initial report must include active issues.'
Assert-True ($initial.Body -match 'plugin-b.*OK') 'Initial report must include clean repositories.'

$unchanged = Get-RepoWatchNotification -Results $current -PreviousIssuesByName @{
    'plugin-a' = @('deployment-drift')
    'plugin-b' = @()
} -IsInitial $false
Assert-True (-not $unchanged.ShouldSend) 'Unchanged status must not send another email.'

$changed = Get-RepoWatchNotification -Results @(
    [pscustomobject]@{ Name = 'plugin-a'; Issues = @('deployment-drift', 'working-tree'); Deploy = $null }
) -PreviousIssuesByName @{ 'plugin-a' = @('deployment-drift') } -IsInitial $false
Assert-True $changed.ShouldSend 'New issue category must trigger an email.'
Assert-True ($changed.Body -match 'working-tree') 'Change report must name the new issue category.'

$recovered = Get-RepoWatchNotification -Results @(
    [pscustomobject]@{ Name = 'plugin-a'; Issues = @(); Deploy = $null }
) -PreviousIssuesByName @{ 'plugin-a' = @('deployment-drift') } -IsInitial $false
Assert-True $recovered.ShouldSend 'Recovery must trigger an email.'
Assert-True ($recovered.Body -match '恢复') 'Recovery report must say the repository recovered.'

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
