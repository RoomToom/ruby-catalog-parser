param(
    [ValidateSet('run', 'test', 'lint', 'install', 'config', 'worker')]
    [string]$Task = 'run',
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$AppArgs
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$rubyCommand = Get-Command ruby -ErrorAction SilentlyContinue
if ($rubyCommand) {
    $rubyBin = Split-Path -Parent $rubyCommand.Source
} elseif (Test-Path -LiteralPath 'D:\Ruby\Ruby40-x64\bin\ruby.exe') {
    $rubyBin = 'D:\Ruby\Ruby40-x64\bin'
} else {
    throw 'Ruby is not in PATH. Open Start Command Prompt with Ruby, or add your Ruby bin directory to PATH.'
}
$env:Path = $rubyBin + ';' + $env:Path
$env:BUNDLE_PATH = Join-Path $projectRoot 'vendor/bundle'
$env:BUNDLE_USER_HOME = Join-Path $projectRoot 'tmp/bundler'
$env:RUBOCOP_CACHE_ROOT = Join-Path $projectRoot 'tmp/rubocop'
Push-Location $projectRoot
try {
    switch ($Task) {
        'install' { & bundle install }
        'run' { & bundle exec ruby main.rb @AppArgs }
        'test' { & bundle exec rake test }
        'lint' { & bundle exec rubocop @AppArgs }
        'config' { & bundle exec ruby main.rb --show-config }
        'worker' { & bundle exec sidekiq -r ./config/sidekiq_boot.rb -q archives -c 2 }
    }
    $taskExitCode = $LASTEXITCODE
} finally {
    Pop-Location
}
exit $taskExitCode
