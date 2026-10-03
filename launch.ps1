param([switch]$Editor)
$ErrorActionPreference = 'Stop'
$projectDirectory = $PSScriptRoot
$candidate = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\godot.exe'
if (-not (Test-Path -LiteralPath $candidate)) {
    $godotCommand = Get-Command godot -ErrorAction SilentlyContinue
    if ($godotCommand) {
        $candidate = $godotCommand.Source
    } else {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show('请先安装 Godot 4，或在 Godot 项目管理器中导入此目录的 project.godot。', '夜色牌局') | Out-Null
        exit 1
    }
}
$projectArguments = @('--path', ('"' + $projectDirectory + '"'))
if ($Editor) {
    Start-Process -FilePath $candidate -ArgumentList (@('--editor') + $projectArguments) -WorkingDirectory $projectDirectory
    exit 0
}
# A downloaded checkout has no .godot cache. Import classes/assets before playing.
$cacheDirectory = Join-Path $projectDirectory '.godot'
New-Item -ItemType Directory -Path $cacheDirectory -Force | Out-Null
$importLog = Join-Path $cacheDirectory 'launch-import.log'
$importArguments = @('--headless', '--editor', '--import', '--quit', '--log-file', ('"' + $importLog + '"')) + $projectArguments
$importProcess = Start-Process -FilePath $candidate -ArgumentList $importArguments -WorkingDirectory $projectDirectory -WindowStyle Hidden -Wait -PassThru
if ($importProcess.ExitCode -ne 0) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show('项目导入失败，请使用 Godot 编辑器打开 project.godot 查看错误。', '夜色牌局') | Out-Null
    exit 1
}
Start-Process -FilePath $candidate -ArgumentList $projectArguments -WorkingDirectory $projectDirectory
