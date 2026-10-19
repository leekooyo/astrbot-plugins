function Get-RepoWatchNotification {
    param(
        [Parameter(Mandatory = $true)][object[]]$Results,
        [hashtable]$PreviousSignaturesByName = @{}
    )

    $actionableIssues = @('deployment-drift', 'working-tree', 'local-ahead')
    $pending = [Collections.Generic.List[object]]::new()
    $nextSignatures = @{}
    $changed = $false
    foreach ($result in $Results) {
        $name = [string]$result.Name
        if (@($result.Issues) -contains 'check-failed') {
            if ($PreviousSignaturesByName.ContainsKey($name)) { $nextSignatures[$name] = [string]$PreviousSignaturesByName[$name] }
            continue
        }
        $issues = @($result.Issues | Where-Object { $_ -in $actionableIssues } | Sort-Object -Unique)
        if ($issues.Count -eq 0) { continue }
        $pending.Add($result)
        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            $bytes = [Text.Encoding]::UTF8.GetBytes(('{0}|{1}|{2}' -f $name, ($issues -join ','), [string]$result.Fingerprint))
            $signature = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
        } finally {
            $sha.Dispose()
        }
        $nextSignatures[$name] = $signature
        if ([string]$PreviousSignaturesByName[$name] -ne $signature) { $changed = $true }
    }
    if (-not $changed) {
        return [pscustomobject]@{ ShouldSend = $false; SignaturesByName = $nextSignatures; Subject = ''; Body = '' }
    }

    $orderedPending = @($pending | Sort-Object Name)
    $lines = [Collections.Generic.List[string]]::new()
    $index = 0
    foreach ($result in $orderedPending) {
        $index++
        $lines.Add(('{0}. {1}' -f $index, [string]$result.Name))
        if (@($result.Issues) -contains 'deployment-drift') {
            $details = if ($result.Deploy) { '（内容不同 {0}，仓库有但运行目录缺少 {1}，运行目录新增 {2}）' -f $result.Deploy.Different, $result.Deploy.Missing, $result.Deploy.Unexpected } else { '' }
            $lines.Add(('   · 运行目录与仓库不同{0}。请核对并将需保留的改动同步到仓库。' -f $details))
        }
        if (@($result.Issues) -contains 'working-tree') {
            $lines.Add('   · 仓库中有未提交或未跟踪的文件。请检查、提交并推送。')
        }
        if (@($result.Issues) -contains 'local-ahead') {
            $lines.Add('   · 本地提交领先于上次记录的远端版本。请联网核对后推送。')
        }
        $lines.Add('')
    }

    $subject = '【RepoWatch】{0} 个仓库待核对并同步 GitHub' -f $orderedPending.Count
    $body = @(
        ('发现 {0} 个仓库有本地改动需要核对。' -f $orderedPending.Count)
        ('检查时间：{0}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
        ''
        $lines.ToArray()
        '请确认改动是否需要保留，再同步、提交和推送。内容不变时不会重复提醒。'
        '此邮件由本机 RepoWatch 发送；未发送文件内容或凭据。'
    ) -join "`r`n"
    [pscustomobject]@{ ShouldSend = $true; SignaturesByName = $nextSignatures; Subject = $subject; Body = $body }
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
