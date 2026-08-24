# ============================================================
#  DeepSeek Harness 新电脑一键安装脚本
#  用法: powershell -ExecutionPolicy Bypass -File setup-new-pc.ps1
#  作用: 创建工作区 + launcher 文件 + 桌面 harness 快捷方式(彩色图标)
# ============================================================
param(
    # 工作区位置，默认为 桌面\DeepSeek workSpace（可用 -Workspace "D:\其他路径" 覆盖）
    [string]$Workspace = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'DeepSeek workSpace'),
    [switch]$NoPause   # 自动化调用时不暂停等待回车
)
$ErrorActionPreference = 'Stop'
Write-Host '=== DeepSeek Harness 安装 ===' -ForegroundColor Cyan

# ---------- 1. 环境检查 ----------
$node = Get-Command node -ErrorAction SilentlyContinue
$npx  = Get-Command npx.cmd -ErrorAction SilentlyContinue
if (-not $npx) { $npx = Get-Command npx -ErrorAction SilentlyContinue }
if ($node) { Write-Host "[OK] Node.js $($node.Version)  ($($node.Source))" }
else {
    Write-Host '[缺失] 未检测到 Node.js！' -ForegroundColor Red
    Write-Host '       请先到 https://nodejs.org 安装 LTS 版，然后重新双击 harness 图标即可。' -ForegroundColor Yellow
}

# ---------- 2. 创建目录并复制文件 ----------
$src      = $PSScriptRoot
$launcher = Join-Path $Workspace 'launcher'
New-Item -ItemType Directory -Force -Path $launcher | Out-Null
foreach ($f in @('start-harness.ps1', 'update-plugins.ps1', 'deepseek-color.ico')) {
    $from = Join-Path $src $f
    $to   = Join-Path $launcher $f
    if (-not (Test-Path -LiteralPath $from)) { Write-Host "[警告] 安装包缺少 $f，跳过" -ForegroundColor Yellow; continue }
    if ((Resolve-Path -LiteralPath $from).Path -eq (Resolve-Path -LiteralPath $to -ErrorAction SilentlyContinue).Path) { continue }  # 源=目标，本机重装
    Copy-Item -LiteralPath $from -Destination $to -Force
}
Write-Host "[OK] 工作区: $Workspace"
Write-Host "[OK] 启动文件: $launcher\start-harness.ps1"

# ---------- 3. 创建桌面快捷方式 ----------
$pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
$target = if ($pwsh) { $pwsh.Source } else { "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" }
$shellTs = if ($pwsh) { 'PowerShell 7' } else { 'Windows PowerShell 5.1 (系统自带)' }

$ws   = New-Object -ComObject WScript.Shell
$lnk  = $ws.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'harness.lnk'))
$lnk.TargetPath    = $target
$lnk.Arguments     = "-NoProfile -ExecutionPolicy Bypass -File `"$launcher\start-harness.ps1`""
$lnk.WorkingDirectory = $Workspace
$lnk.IconLocation  = "$launcher\deepseek-color.ico,0"
$lnk.WindowStyle   = 7
$lnk.Description   = 'DeepSeek Harness Web GUI (127.0.0.1:3080)'
$lnk.Save()
ie4uinit.exe -show 2>$null
Write-Host "[OK] 桌面快捷方式: harness  (使用 $shellTs)"
Write-Host "[OK] 图标: $launcher\deepseek-color.ico"

# ---------- 4. 完成提示 ----------
Write-Host ''
Write-Host '=== 安装完成 ===' -ForegroundColor Green
if ($node) {
    Write-Host '双击桌面 harness 图标即可启动。首次启动会自动初始化，' 
    Write-Host '并在浏览器里要求填写 API 密钥（只需一次），之后永久记住。'
} else {
    Write-Host '先安装 Node.js，再双击桌面 harness 图标。' -ForegroundColor Yellow
}
if (-not $NoPause) { Read-Host '按回车键关闭' }
