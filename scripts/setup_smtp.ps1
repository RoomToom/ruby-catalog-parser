param(
    [string]$Sender = '',
    [string]$Recipient = 'tokarchuk.roman@chnu.edu.ua',
    [string]$SmtpServer = 'smtp.gmail.com'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
try {
    if ([string]::IsNullOrWhiteSpace($Sender)) { $Sender = Read-Host 'Sender Gmail address' }
    if ($Sender -notmatch '^[^\s@]+@[^\s@]+\.[^\s@]+$') { throw 'Enter a valid sender email address.' }
    Write-Host "SMTP sender: $Sender"
    Write-Host "Recipient: $Recipient"
    Write-Host "Server: ${SmtpServer}:587 (STARTTLS)"
    Write-Host 'Enter a Google app password without spaces, NOT your normal account password.'
    Write-Host 'It will be encrypted for this Windows account and excluded from Git and archives.'
    $securePassword = Read-Host 'App password (input hidden)' -AsSecureString
    if ($securePassword.Length -eq 0) { throw 'App password is required.' }
    $credential = New-Object System.Management.Automation.PSCredential($Sender, $securePassword)
    $settings = [pscustomobject]@{
        Server = $SmtpServer
        Recipient = $Recipient
        Credential = $credential
    }
    $settings | Export-Clixml -LiteralPath (Join-Path $projectRoot '.smtp.local.xml')
    Write-Host 'Settings saved. Checking SMTP authentication; no email is sent by this check.'
    & (Join-Path $PSScriptRoot 'run.ps1') smtp-check
    exit $LASTEXITCODE
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
