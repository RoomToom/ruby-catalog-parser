function Get-LabSmtpEnvironment {
    param([string]$SettingsPath)
    if (-not (Test-Path -LiteralPath $SettingsPath)) { return @{} }
    try {
        $settings = Import-Clixml -LiteralPath $SettingsPath
        $password = $settings.Credential.GetNetworkCredential().Password
        if ([string]::IsNullOrWhiteSpace($password)) { throw 'Empty credential' }
        return @{
            SMTP_HOST = $settings.Server
            SMTP_PORT = '587'
            SMTP_STARTTLS = 'true'
            SMTP_FROM = $settings.Credential.UserName
            SMTP_USER = $settings.Credential.UserName
            SMTP_PASSWORD = $password
            ARCHIVE_EMAIL = $settings.Recipient
        }
    } catch {
        throw 'Cannot read local SMTP settings. Run setup_smtp.cmd under your Windows account again.'
    }
}
