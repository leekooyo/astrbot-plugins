function Get-RepoWatchNotification {
    param(
        [Parameter(Mandatory = $true)][object[]]$Results,
        [Parameter(Mandatory = $true)][hashtable]$PreviousIssuesByName,
        [hashtable]$PreviousFingerprintByName = @{},
        [Parameter(Mandatory = $true)][bool]$IsInitial
    )

    $lines = [Collections.Generic.List[string]]::new()
    $changed = $false
    foreach ($result in $Results) {
        $name = [string]$result.Name
        $currentIssues = @($result.Issues | Where-Object { $_ } | Sort-Object -Unique)
        if ($IsInitial) {
            $changed = $true
            $lines.Add(('{0}: {1}' -f $name, $(if ($currentIssues.Count) { $currentIssues -join ', ' } else { 'OK' })))
            continue
        }

        $previousIssues = @($PreviousIssuesByName[$name] | Where-Object { $_ } | Sort-Object -Unique)
        $issuesChanged = ($previousIssues -join ',') -ne ($currentIssues -join ',')
        $previousFingerprint = [string]$PreviousFingerprintByName[$name]
        $currentFingerprint = if ($result.PSObject.Properties['Fingerprint']) { [string]$result.Fingerprint } else { '' }
        $contentChanged = $currentIssues.Count -gt 0 -and $previousFingerprint -and $currentFingerprint -and $previousFingerprint -ne $currentFingerprint
        if (-not $issuesChanged -and -not $contentChanged) { continue }
        $changed = $true
        if ($contentChanged -and -not $issuesChanged) {
            $lines.Add(('{0}: 差异内容已变化；当前问题：{1}' -f $name, ($currentIssues -join ', ')))
        } elseif ($currentIssues.Count) {
            $lines.Add(('{0}: {1}' -f $name, ($currentIssues -join ', ')))
        } elseif ($previousIssues.Count) {
            $lines.Add(('{0}: 已恢复同步' -f $name))
        }
    }

    if (-not $changed) {
        return [pscustomobject]@{ ShouldSend = $false; Subject = ''; Body = '' }
    }

    if ($IsInitial -and @($lines | Where-Object { $_ -notmatch ': OK$' }).Count -eq 0) {
        $lines.Insert(0, '所有受监测仓库当前均正常。')
    }
    $subject = if ($IsInitial) { 'RepoWatch 首次状态报告' } else { 'RepoWatch 仓库状态变化' }
    $body = @(
        ('检查时间：{0}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
        ''
        $lines.ToArray()
        ''
        '此邮件由本机 RepoWatch 监测器发送。'
    ) -join "`r`n"
    [pscustomobject]@{ ShouldSend = $true; Subject = $subject; Body = $body }
}

function Save-RepoWatchCredential {
    param(
        [Parameter(Mandatory = $true)][string]$CredentialPath,
        [Parameter(Mandatory = $true)][Security.SecureString]$SecurePassword
    )
    $path = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($CredentialPath))
    $directory = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    ConvertFrom-SecureString -SecureString $SecurePassword | Set-Content -LiteralPath $path -Encoding ASCII
}

function Read-RepoWatchPassword {
    param([Parameter(Mandatory = $true)][string]$CredentialPath)
    $path = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($CredentialPath))
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'SMTP credential file is missing.' }
    $encryptedPassword = (Get-Content -LiteralPath $path -Raw).Trim()
    $securePassword = ConvertTo-SecureString -String $encryptedPassword
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    try {
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Send-RepoWatchEmail {
    param(
        [Parameter(Mandatory = $true)]$Smtp,
        [Parameter(Mandatory = $true)][string]$Subject,
        [Parameter(Mandatory = $true)][string]$Body
    )
    foreach ($required in @('server', 'port', 'username', 'from', 'to', 'credentialPath', 'enableSsl')) {
        if (-not $Smtp.PSObject.Properties[$required] -or $null -eq $Smtp.$required -or [string]::IsNullOrWhiteSpace([string]$Smtp.$required)) {
            throw "SMTP configuration is missing '$required'."
        }
    }
    if ([int]$Smtp.port -lt 1 -or [int]$Smtp.port -gt 65535) { throw 'SMTP port is invalid.' }

    $password = Read-RepoWatchPassword -CredentialPath ([string]$Smtp.credentialPath)
    $message = [System.Net.Mail.MailMessage]::new(
        [System.Net.Mail.MailAddress]::new([string]$Smtp.from),
        [System.Net.Mail.MailAddress]::new([string]$Smtp.to)
    )
    $client = [System.Net.Mail.SmtpClient]::new([string]$Smtp.server, [int]$Smtp.port)
    try {
        $message.Subject = $Subject
        $message.SubjectEncoding = [System.Text.Encoding]::UTF8
        $message.Body = $Body
        $message.BodyEncoding = [System.Text.Encoding]::UTF8
        $message.IsBodyHtml = $false
        $client.EnableSsl = [bool]$Smtp.enableSsl
        $client.UseDefaultCredentials = $false
        $client.Credentials = [System.Net.NetworkCredential]::new([string]$Smtp.username, $password)
        $client.Timeout = 20000
        $client.Send($message)
    } finally {
        $message.Dispose()
        $client.Dispose()
        $password = $null
    }
}
