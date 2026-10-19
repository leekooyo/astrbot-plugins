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
$sourceScript = Join-Path $PSScriptRoot 'Watch-Repos.ps1'
if (-not (Test-Path -LiteralPath $sourceScript -PathType Leaf)) { throw "Missing checker script: $sourceScript" }
$installedScript = Join-Path (Split-Path -Parent $config) 'Watch-Repos.ps1'
$sourceModule = Join-Path $PSScriptRoot 'RepoWatch.Notifications.ps1'
$sourceInitializer = Join-Path $PSScriptRoot 'Initialize-RepoWatchEmail.ps1'
if (-not (Test-Path -LiteralPath $sourceModule -PathType Leaf)) { throw "Missing notification module: $sourceModule" }
if (-not (Test-Path -LiteralPath $sourceInitializer -PathType Leaf)) { throw "Missing email initializer: $sourceInitializer" }
$installedModule = Join-Path (Split-Path -Parent $config) 'RepoWatch.Notifications.ps1'
$installedInitializer = Join-Path (Split-Path -Parent $config) 'Initialize-RepoWatchEmail.ps1'
Copy-Item -LiteralPath $sourceScript -Destination $installedScript -Force
Copy-Item -LiteralPath $sourceModule -Destination $installedModule -Force
Copy-Item -LiteralPath $sourceInitializer -Destination $installedInitializer -Force

$powershellExe = (Get-Command powershell.exe -ErrorAction Stop).Source
$arguments = "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$installedScript`" -ConfigPath `"$config`""
$action = New-ScheduledTaskAction -Execute $powershellExe -Argument $arguments -WorkingDirectory (Split-Path -Parent $installedScript)
$start = (Get-Date).AddMinutes(2)
$trigger = New-ScheduledTaskTrigger -Once -At $start -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 3650)
$user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

Register-ScheduledTask -TaskName $taskName -Description 'Checks configured Git repositories and deployment folders hourly; emails only for pending local changes.' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Write-Output "Installed scheduled task: $taskName"
Write-Output "Installed checker copy: $installedScript"
Write-Output "Installed email initializer: $installedInitializer"
Write-Output "Runs as $user when that user is logged in; first run is scheduled for $($start.ToString('yyyy-MM-dd HH:mm'))."
Write-Output 'The trigger repeats hourly for 10 years; rerun this installer before it expires.'
