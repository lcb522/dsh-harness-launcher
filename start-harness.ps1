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
if (-not (Get-Command dsh -ErrorAction SilentlyContinue)) {
    Write-Host "错误: 未找到 dsh 命令，请先安装 Node.js (LTS) 后执行: npm install -g @deepseek-ai/dsh" -ForegroundColor Red
    Read-Host '按回车键关闭'
    exit 1
}

Write-Host "正在启动 DeepSeek Harness（首次约需几秒到十几秒）..."
Write-Host "工作目录: $workspace"
Write-Host "提示: 关闭本窗口即停止服务；再次双击快捷方式会直接打开浏览器。"

# ---- 自动更新：本地版本落后于 npm latest 时先升级（失败不阻塞启动）----
try {
    $updLog = "$env:USERPROFILE\.dsh\logs\autoupdate.log"
    New-Item -ItemType Directory -Force -Path (Split-Path $updLog) | Out-Null
    $local  = (& dsh --version 2>$null | Select-Object -First 1)
    $latest = (& npm view @deepseek-ai/dsh version 2>$null)
    if ($latest -and $local -and ($local.Trim() -ne $latest.Trim())) {
        Write-Host "发现新版本 $local -> $latest，正在升级..."
        "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] upgrading $local -> $latest" | Add-Content $updLog
        & npm install -g "@deepseek-ai/dsh@$latest" 2>>$updLog | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "已升级到 $latest" -ForegroundColor Green
            "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] upgraded OK" | Add-Content $updLog
        } else {
            Write-Host "升级失败，继续使用当前版本 $local" -ForegroundColor Yellow
            "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] upgrade FAILED" | Add-Content $updLog
        }
    }
} catch {
    Write-Host "版本检查跳过：$($_.Exception.Message)" -ForegroundColor DarkGray
}

# ---- 插件自动更新：web profile 里 npm 安装的插件包（每天最多查一次，失败不阻塞）----
try {
    $stampFile = "$env:USERPROFILE\.dsh\logs\plugin-autoupdate.stamp"
    $profileDir = "$env:USERPROFILE\.dsh\profiles\web"
    if (Test-Path "$profileDir\package.json") {
        $needCheck = $true
        if (Test-Path $stampFile) {
            $last = Get-Content $stampFile -Raw -ErrorAction SilentlyContinue
            if ($last -match '^\d{4}-\d{2}-\d{2}$' -and $last -eq (Get-Date -Format 'yyyy-MM-dd')) { $needCheck = $false }
        }
        if ($needCheck) {
            (Get-Date -Format 'yyyy-MM-dd') | Set-Content $stampFile -Force
            # 只更新 profile dependencies 里声明的插件包（官方 bundles 不在 dependencies，天然排除；
            # 自研插件走 junction 安装、无 npm 源，也不受影响）
            $deps = (Get-Content "$profileDir\package.json" -Raw | ConvertFrom-Json).dependencies
            $npmSpecs = @()
            if ($deps) { $npmSpecs = $deps.PSObject.Properties.Name | Where-Object { $_ -notlike '@deepseek-ai/*' } }
            $toUpdate = @()
            foreach ($spec in ($npmSpecs | Sort-Object -Unique)) {
                $localDir = Join-Path $profileDir ("node_modules\" + ($spec -replace '/', '\'))
                if (-not (Test-Path "$localDir\package.json")) { continue }
                $local = (Get-Content "$localDir\package.json" -Raw | ConvertFrom-Json).version
                $latest = & npm view $spec version 2>$null
                if ($latest -and $local -and ($local.Trim() -ne $latest.Trim())) { $toUpdate += "$spec@$latest" }
            }
            if ($toUpdate.Count -gt 0) {
                Write-Host "插件有更新: $($toUpdate -join ', ')，正在升级..."
                "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] plugins: $($toUpdate -join ', ')" | Add-Content "$env:USERPROFILE\.dsh\logs\autoupdate.log"
                Push-Location $profileDir
                & npm install ($toUpdate | ForEach-Object { $_ }) --save --registry=https://registry.npmmirror.com 2>>"$env:USERPROFILE\.dsh\logs\autoupdate.log" | Out-Null
                $ok = $LASTEXITCODE -eq 0
                Pop-Location
                if ($ok) { Write-Host "插件已更新到最新" -ForegroundColor Green }
                else { Write-Host "插件更新失败，继续使用当前版本" -ForegroundColor Yellow }
            } else {
                Write-Host "插件均为最新" -ForegroundColor DarkGray
            }
        } else {
            Write-Host "插件今日已检查过，跳过" -ForegroundColor DarkGray
        }
    }
} catch {
    Write-Host "插件更新跳过：$($_.Exception.Message)" -ForegroundColor DarkGray
}

$server = Start-Process -FilePath "$env:ComSpec" `
    -ArgumentList '/c', 'dsh', 'web', '--port', '3080', '--no-open' `
    -WorkingDirectory $workspace -NoNewWindow -PassThru

Write-Host "服务进程 PID: $($server.Id)"

# 等服务就绪后自动打开浏览器（带 90 秒超时与多路兜底）
$opened = $false
$deadline = (Get-Date).AddSeconds(90)
while (-not $opened -and (Get-Date) -lt $deadline) {
    if (Test-Server) {
        $opened = $true
        Write-Host "服务已就绪: $url"
        if (-not $NoBrowser) { Start-Process $url }
        continue
    }
    if ($server.HasExited) {
        Start-Sleep -Seconds 2
        if (Test-Server) {
            $opened = $true
            Write-Host "服务进程已重托管，端口可用: $url"
            if (-not $NoBrowser) { Start-Process $url }
        } else {
            Write-Host "服务进程启动失败（exit code $($server.ExitCode)）" -ForegroundColor Red
            Get-Content "$env:USERPROFILE\.dsh\logs\autoupdate.log" -Tail 5 -ErrorAction SilentlyContinue
        }
        break
    }
    Start-Sleep -Milliseconds 500
}
if (-not $opened -and -not $NoBrowser -and (Test-Server)) {
    Write-Host "兜底：服务可用，打开浏览器"
    Start-Process $url
}

Write-Host "服务器已停止，本窗口将在 10 秒后自动关闭..."
Start-Sleep -Seconds 10
