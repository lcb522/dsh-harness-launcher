# DeepSeek Harness 一键启动器（便携版，可在任何机器上运行）
# 工作区 = 本脚本所在 launcher 目录的上一级目录
param([switch]$NoBrowser)

$ErrorActionPreference = 'Continue'
$url       = 'http://127.0.0.1:3080'
$workspace = Split-Path -Parent $PSScriptRoot

$Host.UI.RawUI.WindowTitle = 'DeepSeek Harness'

function Test-Server {
    try { $null = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 2; return $true }
    catch { return $false }
}

# 已经在运行？直接打开浏览器即可
if (Test-Server) {
    Write-Host "DeepSeek Harness 已在运行，直接打开浏览器 $url"
    if (-not $NoBrowser) { Start-Process $url }
    exit 0
}

# 检查 Node.js 环境
if (-not (Get-Command npx.cmd -ErrorAction SilentlyContinue) -and -not (Get-Command npx -ErrorAction SilentlyContinue)) {
    Write-Host "错误: 未找到 npx，请先安装 Node.js (LTS): https://nodejs.org" -ForegroundColor Red
    Write-Host "安装完成后重新双击 harness 快捷方式即可。"
    Read-Host '按回车键关闭'
    exit 1
}

Write-Host "正在启动 DeepSeek Harness（首次约需几秒到十几秒）..."
Write-Host "工作目录: $workspace"
Write-Host "提示: 关闭本窗口即停止服务；再次双击快捷方式会直接打开浏览器。"

$server = Start-Process -FilePath "$env:ComSpec" `
    -ArgumentList '/c', 'npx', '-y', '@deepseek-ai/dsh', 'web', '--port', '3080' `
    -WorkingDirectory $workspace -NoNewWindow -PassThru

# 等服务就绪后自动打开浏览器
$opened = $false
while (-not $server.HasExited) {
    if (-not $opened -and (Test-Server)) {
        $opened = $true
        Write-Host "服务已就绪: $url"
        if (-not $NoBrowser) { Start-Process $url }
    }
    Start-Sleep -Milliseconds 500
}

Write-Host "服务器已停止，本窗口将在 10 秒后自动关闭..."
Start-Sleep -Seconds 10
