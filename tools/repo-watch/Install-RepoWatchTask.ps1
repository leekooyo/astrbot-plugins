[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,
    [switch]$Uninstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$taskName = 'RepoWatch-Hourly'

if ($Uninstall) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Output "Removed scheduled task: $taskName"
    exit 0
}

$config = (Resolve-Path -LiteralPath $ConfigPath).Path
$watchScript = Join-Path $PSScriptRoot 'Watch-Repos.ps1'
if (-not (Test-Path -LiteralPath $watchScript -PathType Leaf)) { throw "Missing checker script: $watchScript" }

$powershellExe = (Get-Command powershell.exe -ErrorAction Stop).Source
$arguments = "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$watchScript`" -ConfigPath `"$config`""
$action = New-ScheduledTaskAction -Execute $powershellExe -Argument $arguments -WorkingDirectory $PSScriptRoot
$start = (Get-Date).AddMinutes(2)
$trigger = New-ScheduledTaskTrigger -Once -At $start -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 3650)
$user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

Register-ScheduledTask -TaskName $taskName -Description 'Checks configured Git repositories and deployment folders hourly; sends state-change notifications.' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Write-Output "Installed scheduled task: $taskName"
Write-Output "Runs as $user when that user is logged in; first run is scheduled for $($start.ToString('yyyy-MM-dd HH:mm'))."
Write-Output 'The trigger repeats hourly for 10 years; rerun this installer before it expires.'
