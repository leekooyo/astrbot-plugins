[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'RepoWatch.Notifications.ps1')

$configFile = (Resolve-Path -LiteralPath $ConfigPath).Path
$config = Get-Content -LiteralPath $configFile -Raw | ConvertFrom-Json
if (-not $config.PSObject.Properties['smtp']) { throw 'SMTP settings are missing from the local configuration.' }
$credentialPath = [string]$config.smtp.credentialPath
if ([string]::IsNullOrWhiteSpace($credentialPath)) { throw 'SMTP credentialPath is missing from the local configuration.' }

$securePassword = Read-Host 'Enter the new QQ Mail authorization code (input is hidden)' -AsSecureString
if ($securePassword.Length -eq 0) { throw 'The authorization code cannot be empty.' }
Save-RepoWatchCredential -CredentialPath $credentialPath -SecurePassword $securePassword
Write-Output 'Saved the encrypted SMTP credential for the current Windows user.'

$watcherPath = Join-Path $PSScriptRoot 'Watch-Repos.ps1'
& $watcherPath -ConfigPath $configFile
