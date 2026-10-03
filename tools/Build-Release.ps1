param(
    [string]$OutputDirectory = '',
    [string]$GodotExecutable = '',
    [string]$JavaHome = $env:JAVA_HOME,
    [switch]$CreateAndroidKey
)
$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $projectDirectory 'build' }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
if (-not $GodotExecutable) {
    $GodotExecutable = Join-Path $env:LOCALAPPDATA 'Microsoft/WinGet/Links/godot_console.exe'
    if (-not (Test-Path -LiteralPath $GodotExecutable)) {
        $GodotExecutable = (Get-Command godot_console -ErrorAction Stop).Source
    }
}
$projectText = [IO.File]::ReadAllText((Join-Path $projectDirectory 'project.godot'))
$version = [regex]::Match($projectText, 'config/version="([^"]+)"').Groups[1].Value
if (-not $version) { throw 'Set config/version in project.godot first.' }
$privateDirectory = Join-Path $projectDirectory '.private'
$signingPath = Join-Path $privateDirectory 'android-signing.json'
$envNames = @('JAVA_HOME', 'GODOT_ANDROID_KEYSTORE_RELEASE_PATH', 'GODOT_ANDROID_KEYSTORE_RELEASE_USER', 'GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD')
$savedEnvironment = @{}
foreach ($name in $envNames) { $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
function Invoke-GodotChecked([string[]]$GodotArguments, [string]$LogName) {
    $log = (& $GodotExecutable @GodotArguments 2>&1 | Out-String)
    $result = $LASTEXITCODE
    [IO.File]::WriteAllText((Join-Path $OutputDirectory $LogName), $log, [Text.UTF8Encoding]::new($false))
    if ($result -ne 0 -or $log -match 'SCRIPT ERROR:|ERROR:') {
        throw "Godot failed; inspect $LogName in $OutputDirectory"
    }
}
try {
    if ($JavaHome) { $env:JAVA_HOME = $JavaHome }
    if (-not $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH) {
        if (-not (Test-Path -LiteralPath $signingPath)) {
            if (-not $CreateAndroidKey) { throw 'Provide signing environment variables or run once with -CreateAndroidKey. Keep the generated .private directory for future updates.' }
            New-Item -ItemType Directory -Force -Path $privateDirectory | Out-Null
            [IO.File]::WriteAllText((Join-Path $privateDirectory '.gdignore'), '')
            $keyPath = Join-Path $privateDirectory 'nightfall-release.keystore'
            if (Test-Path -LiteralPath $keyPath) { throw 'Existing keystore found without signing metadata; restore its metadata instead of replacing it.' }
            $randomBytes = New-Object byte[] 32
            $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
            $rng.GetBytes($randomBytes)
            $rng.Dispose()
            $password = ([BitConverter]::ToString($randomBytes)).Replace('-', '').ToLowerInvariant()
            $env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = $password
            $keytool = Join-Path $env:JAVA_HOME 'bin/keytool.exe'
            if (-not (Test-Path -LiteralPath $keytool)) { throw 'Pass -JavaHome with a JDK containing keytool.' }
            $keyLog = (& $keytool -genkeypair -keystore $keyPath -storepass:env GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD -keypass:env GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD -alias nightfall-release -keyalg RSA -keysize 3072 -validity 10000 -dname 'CN=Nightfall Poker,OU=Games,O=Eser-Tired,C=CN' 2>&1 | Out-String)
            if ($LASTEXITCODE -ne 0) { throw 'Android signing key generation failed.' }
            $metadata = @{ path = $keyPath; alias = 'nightfall-release'; password = $password } | ConvertTo-Json
            [IO.File]::WriteAllText($signingPath, $metadata, [Text.UTF8Encoding]::new($false))
            Write-Output 'Created persistent Android signing key in ignored .private directory. Back up this directory privately.'
        }
        $signing = [IO.File]::ReadAllText($signingPath) | ConvertFrom-Json
        $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = $signing.path
        $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = $signing.alias
        $env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = $signing.password
    }
    if (-not $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER -or -not $env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD) { throw 'Android release signing alias/password missing.' }
    Invoke-GodotChecked @('--headless', '--editor', '--path', $projectDirectory, '--import', '--quit') 'import.log'
    $windowsFile = Join-Path $OutputDirectory "NightfallPoker-v$version-Windows-x64.exe"
    $androidFile = Join-Path $OutputDirectory "NightfallPoker-v$version-Android.apk"
    Invoke-GodotChecked @('--headless', '--path', $projectDirectory, '--export-release', 'Windows', $windowsFile) 'windows-export.log'
    Write-Output "Exported $windowsFile"
    Invoke-GodotChecked @('--headless', '--path', $projectDirectory, '--export-release', 'Android', $androidFile) 'android-export.log'
    Write-Output "Exported $androidFile"
    $hashLines = foreach ($file in @($windowsFile, $androidFile)) {
        if (-not (Test-Path -LiteralPath $file)) { throw "Export missing: $file" }
        $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $([IO.Path]::GetFileName($file))"
    }
    [IO.File]::WriteAllLines((Join-Path $OutputDirectory 'SHA256SUMS.txt'), $hashLines, [Text.UTF8Encoding]::new($false))
} finally {
    foreach ($name in $envNames) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process') }
}
