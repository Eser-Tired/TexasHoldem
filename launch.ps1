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
Start-Process -FilePath $candidate -ArgumentList @('--path', ('"' + $projectDirectory + '"')) -WorkingDirectory $projectDirectory
