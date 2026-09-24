$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$toolsPath = Join-Path $projectRoot 'tmp/tools'
$redisExecutable = Join-Path $toolsPath 'redis/Redis-7.4.9-Windows-x64-msys2/redis-server.exe'
if (Test-Path -LiteralPath $redisExecutable) { return }
New-Item -ItemType Directory -Path $toolsPath -Force | Out-Null
$archivePath = Join-Path $toolsPath 'redis.zip'
$downloadUrl = 'https://github.com/redis-windows/redis-windows/releases/download/7.4.9/Redis-7.4.9-Windows-x64-msys2.zip'
Write-Host 'Downloading portable Redis 7.4.9 for Windows...'
Invoke-WebRequest -Uri $downloadUrl -OutFile $archivePath -UseBasicParsing
$expectedHash = '98AF6511CA35601CC8D8200A92318E00F9D2D5425A9F7F3E8F699D3BDD59DCF6'
if ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash -ne $expectedHash) {
    throw 'Redis archive checksum mismatch.'
}
Expand-Archive -LiteralPath $archivePath -DestinationPath (Join-Path $toolsPath 'redis') -Force
if (-not (Test-Path -LiteralPath $redisExecutable)) { throw 'Redis executable is missing.' }
Write-Host 'Portable Redis is ready.'
