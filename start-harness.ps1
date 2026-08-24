# ============================================================
#  DeepSeek Harness 一键启动器（便携版，可在任何机器上运行）
#  工作区 = 本脚本所在 launcher 目录的上一级目录
#
#  每次启动的自动更新策略（-SkipUpdate 可跳过）:
#    1) Harness 本体（全局）: 每次检测，落后于 npm latest 就同步更新完再启动（本次即最新）
#    2) 插件全家桶: 每次检测；有新版时同步等待 -PluginUpdateBudgetSec 秒，
#       预算内完成 → 本次生效；超时 → 先启动服务，更新转后台（下次启动生效）
#    服务已在运行时直接打开浏览器，不做任何更新动作。
# ============================================================
param(
    [switch]$NoBrowser,
    [switch]$SkipUpdate,              # 跳过本次更新检查（紧急排查用）
    [int]$PluginUpdateBudgetSec = 20  # 插件更新同步等待预算（秒）
)

$ErrorActionPreference = 'Continue'
$env:NPM_CONFIG_FETCH_TIMEOUT = '15000'   # npm 检查 15 秒超时：离线时快速失败，不卡启动
$env:NPM_CONFIG_FETCH_RETRIES = '1'

$url       = 'http://127.0.0.1:3080'
$workspace = Split-Path -Parent $PSScriptRoot
$updLog    = "$env:USERPROFILE\.dsh\logs\autoupdate.log"

$Host.UI.RawUI.WindowTitle = 'DeepSeek Harness'

function Test-Server {
    try { $null = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 2; return $true }
    catch { return $false }
}
function Write-UpdLog([string]$m) {
    try {
        New-Item -ItemType Directory -Force -Path (Split-Path $updLog) | Out-Null
        "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $m" | Add-Content $updLog
    } catch {}
}

# ---------- 语义化版本比较（返回 -1/0/1，支持 0.1.1-rc.2 这类预发布号） ----------
function ConvertTo-SemVer([string]$v) {
    if ($v -match '^\s*v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.\-]+))?') {
        [pscustomobject]@{ Major=[int]$Matches[1]; Minor=[int]$Matches[2]; Patch=[int]$Matches[3]; Pre=$Matches[4] }
    } else { $null }
}
function Compare-SemVer([string]$a, [string]$b) {
    $x = ConvertTo-SemVer $a; $y = ConvertTo-SemVer $b
    if (-not $x -or -not $y) {
        if ($a -eq $b) { return 0 }
        if ([string]::CompareOrdinal($a,$b) -lt 0) { return -1 } else { return 1 }
    }
    foreach ($k in 'Major','Minor','Patch') {
        if ($x.$k -ne $y.$k) {
            if ($x.$k -lt $y.$k) { return -1 } else { return 1 }
        }
    }
    if ($x.Pre -eq $y.Pre) { return 0 }
    if (-not $x.Pre) { return 1 }            # 无预发布后缀 > 有（1.0.0 > 1.0.0-rc.1）
    if (-not $y.Pre) { return -1 }
    return [math]::Sign([string]::CompareOrdinal($x.Pre, $y.Pre))
}
function Stop-ProcessTree($p) {
    try { $p.Kill($true) } catch { try { $p.Kill() } catch {} }
}
function Get-ShellExe {
    if (Get-Command pwsh -ErrorAction SilentlyContinue) { return (Get-Command pwsh).Source }
    return (Get-Command powershell).Source
}

# ---------- 0. 已在运行：直接开浏览器（不动运行中的服务） ----------
if (Test-Server) {
    Write-Host "DeepSeek Harness 已在运行，直接打开浏览器 $url"
    if (-not $NoBrowser) { Start-Process $url }
    exit 0
}

# ---------- 1. 检查 Node.js 环境 ----------
$npmExe  = (Get-Command npm -ErrorAction SilentlyContinue).Source
$dshExe  = (Get-Command dsh -ErrorAction SilentlyContinue).Source
if (-not $npmExe) {
    Write-Host "错误: 未找到 npm，请先安装 Node.js (LTS): https://nodejs.org" -ForegroundColor Red
    Write-Host "安装完成后重新双击 harness 快捷方式即可。"
    Read-Host '按回车键关闭'
    exit 1
}

$deferredPluginUpdate = $null   # 慢路径标记：目标版本

if (-not $SkipUpdate) {

    # ---------- 2. Harness 本体更新检查（每次启动，同步，落后才动手） ----------
    try {
        $latestDsh = (& $npmExe view '@deepseek-ai/dsh' version 2>$null | Select-Object -Last 1)
        if ($latestDsh) {
            $latestDsh   = $latestDsh.ToString().Trim()
            $globalRoot  = (& $npmExe root -g 2>$null | Select-Object -Last 1).ToString().Trim()
            $gpj         = Join-Path $globalRoot '@deepseek-ai\dsh\package.json'
            $installedDsh = $null
            if (Test-Path $gpj) { try { $installedDsh = (Get-Content $gpj -Raw | ConvertFrom-Json).version } catch {} }

            $needInstall = $false
            if (-not $installedDsh) {
                Write-Host "[更新] 未检测到全局 Harness，安装 $latestDsh ..." -ForegroundColor Cyan
                $needInstall = $true
            } elseif ((Compare-SemVer $installedDsh $latestDsh) -lt 0) {
                Write-Host "[更新] Harness 有新版本: $installedDsh -> $latestDsh，正在更新（约 10-60 秒）..." -ForegroundColor Cyan
                $needInstall = $true
            }

            if ($needInstall) {
                Write-UpdLog "harness: $installedDsh -> $latestDsh"
                # 180 秒硬超时：网络卡死也不至于永远起不来；失败不阻塞启动
                $p = Start-Process $npmExe -ArgumentList 'install','-g','@deepseek-ai/dsh@latest' -NoNewWindow -PassThru
                if (-not $p.WaitForExit(180000)) {
                    Stop-ProcessTree $p
                    Write-Host "[更新] Harness 更新超时，已跳过（本次用当前版本启动）" -ForegroundColor Yellow
                    Write-UpdLog "harness: upgrade TIMEOUT"
                } elseif ($p.ExitCode -eq 0) {
                    Write-Host "[更新] Harness 更新完成: $latestDsh" -ForegroundColor Green
                    Write-UpdLog "harness: upgraded OK -> $latestDsh"
                    $dshExe = (Get-Command dsh -ErrorAction SilentlyContinue).Source
                } else {
                    Write-Host "[更新] Harness 更新失败（exit $($p.ExitCode)），继续用当前版本" -ForegroundColor Yellow
                    Write-UpdLog "harness: upgrade FAILED"
                }
            }
        }
    } catch { Write-Host "[更新] Harness 检查跳过：$($_.Exception.Message)" -ForegroundColor DarkGray }

    # ---------- 2.5 junction 安装的本地插件（如 dsh-sync-panel）：git 检查更新 ----------
    # 这类插件不在 npm 上（node_modules 里是指向源码目录的 junction），
    # npm 通道永远查不到；这里直接对源码 git 仓库做 fetch + 落后才 pull。
    try {
        $nmDir = Join-Path $env:USERPROFILE '.dsh\profiles\web\node_modules'
        if (Test-Path $nmDir) {
            foreach ($entry in (Get-ChildItem $nmDir -Directory -ErrorAction SilentlyContinue)) {
                if ($entry.LinkType -ne 'Junction' -and $entry.LinkType -ne 'SymbolicLink') { continue }
                $target = $entry.Target
                if ($target -is [array]) { $target = $target[0] }
                if (-not $target -or -not (Test-Path -LiteralPath $target)) { continue }

                # 从目标目录向上找 git 仓库根（junction 可能指向仓库的子目录）
                $repo = (& git -C $target rev-parse --show-toplevel 2>$null)
                if (-not $repo -or $LASTEXITCODE -ne 0) { continue }
                $repo = "$repo".Trim()
                $branch = (& git -C $repo branch --show-current 2>$null)
                if (-not $branch) { continue }

                # 有本地改动/未提交内容：跳过（不覆盖用户手上的活）
                $dirty = (& git -C $repo status --porcelain 2>$null)
                if ($dirty) {
                    Write-Host "[更新] 跳过本地插件 $($entry.Name)：源码有未提交改动" -ForegroundColor DarkYellow
                    continue
                }

                # fetch 远端（禁交互凭据；失败即静默跳过，不阻塞启动）
                $env:GIT_TERMINAL_PROMPT = '0'
                & git -C $repo -c http.sslBackend=openssl -c credential.helper= fetch origin 2>$null
                $remoteRef = (& git -C $repo rev-parse --verify "origin/$branch" 2>$null)
                if (-not $remoteRef) { continue }
                $behind = (& git -C $repo rev-list --count "HEAD..origin/$branch" 2>$null)
                if ($behind -and ([int]"$behind" -gt 0)) {
                    Write-Host "[更新] 本地插件 $($entry.Name) 落后远端 $behind 个提交，正在拉取..." -ForegroundColor Cyan
                    $pullOut = & git -C $repo -c http.sslBackend=openssl -c credential.helper= pull --ff-only origin $branch 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "[更新] $($entry.Name) 已更新到最新（本次启动即生效）" -ForegroundColor Green
                        Write-UpdLog "junction $($entry.Name): pulled $behind commit(s)"
                    } else {
                        $firstLine = (($pullOut | Out-String).Trim() -split "`r?`n")[0]
                        Write-Host "[更新] $($entry.Name) 拉取失败：$firstLine" -ForegroundColor Yellow
                        Write-UpdLog "junction $($entry.Name): pull FAILED"
                    }
                }
            }
        }
    } catch { Write-Host "[更新] 本地插件检查跳过：$($_.Exception.Message)" -ForegroundColor DarkGray }

    # ---------- 3. 插件全家桶更新检查（每次启动；预算内同步，超时先启动） ----------
    $updateScript = Join-Path $PSScriptRoot 'update-plugins.ps1'
    if (Test-Path $updateScript) {
        try {
            $latestP = (& $npmExe view '@linxin666/dsh-web-ui-all' version 2>$null | Select-Object -Last 1)
            if ($latestP) {
                $latestP = $latestP.ToString().Trim()
                $ipj = Join-Path $env:USERPROFILE '.dsh\profiles\web\node_modules\@linxin666\dsh-web-ui-all\package.json'
                $installedP = '(未安装)'
                if (Test-Path $ipj) { try { $installedP = (Get-Content $ipj -Raw | ConvertFrom-Json).version } catch {} }

                if ((Compare-SemVer $installedP $latestP) -lt 0) {
                    Write-Host "[更新] 插件全家桶有新版本: $installedP -> $latestP（同步等待最多 $PluginUpdateBudgetSec 秒，超时先启动）..." -ForegroundColor Cyan
                    $up = Start-Process (Get-ShellExe) -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$updateScript`"" -WindowStyle Hidden -PassThru

                    if ($up.WaitForExit($PluginUpdateBudgetSec * 1000)) {
                        # 快路径：预算内完成，本次启动即生效
                        if ($up.ExitCode -eq 0) { Write-Host "[更新] 插件更新完成（$latestP），本次启动即生效" -ForegroundColor Green }
                        else { Write-Host "[更新] 插件更新未成功，详见 launcher\plugin-update.log；本次用当前版本" -ForegroundColor Yellow }
                    } else {
                        # 慢路径：先停掉更新进程（避免与服务启动抢文件），服务就绪后再后台续跑
                        Stop-ProcessTree $up
                        Start-Sleep -Seconds 1
                        $deferredPluginUpdate = $latestP
                        Write-Host "[更新] 插件更新较慢：先启动服务，更新稍后转后台，下次启动生效" -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "[更新] 插件已是最新（$installedP）" -ForegroundColor DarkGray
                }
            }
        } catch { Write-Host "[更新] 插件检查跳过：$($_.Exception.Message)" -ForegroundColor DarkGray }
    }

} else {
    Write-Host "[更新] 已用 -SkipUpdate 跳过更新检查" -ForegroundColor DarkGray
}

# ---------- 4. 启动服务（优先全局 dsh，回退 npx） ----------
Write-Host "正在启动 DeepSeek Harness（首次约需几秒到十几秒）..."
Write-Host "工作目录: $workspace"
Write-Host "提示: 关闭本窗口即停止服务；再次双击快捷方式会直接打开浏览器。"

if ($dshExe) {
    $server = Start-Process -FilePath "$env:ComSpec" `
        -ArgumentList '/c', 'dsh', 'web', '--port', '3080', '--no-open' `
        -WorkingDirectory $workspace -NoNewWindow -PassThru
} else {
    $server = Start-Process -FilePath "$env:ComSpec" `
        -ArgumentList '/c', 'npx', '-y', '@deepseek-ai/dsh', 'web', '--port', '3080', '--no-open' `
        -WorkingDirectory $workspace -NoNewWindow -PassThru
}
Write-Host "服务进程 PID: $($server.Id)"

# ---------- 5. 等服务就绪后自动打开浏览器（90 秒超时 + 多路兜底） ----------
$opened  = $false
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
            Get-Content $updLog -Tail 5 -ErrorAction SilentlyContinue
        }
        break
    }
    Start-Sleep -Milliseconds 500
}
if (-not $opened -and -not $NoBrowser -and (Test-Server)) {
    Write-Host "兜底：服务可用，打开浏览器"
    Start-Process $url
}

# ---------- 6. 慢路径续跑：服务已加载完代码，现在后台更新插件是安全的 ----------
if ($deferredPluginUpdate) {
    $updateScript = Join-Path $PSScriptRoot 'update-plugins.ps1'
    Start-Process (Get-ShellExe) -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$updateScript`"" -WindowStyle Hidden | Out-Null
    Write-Host "[更新] 插件更新已转后台执行（目标 $deferredPluginUpdate），日志: launcher\plugin-update.log，完成后下次启动生效" -ForegroundColor Yellow
    Write-UpdLog "plugins: deferred background update -> $deferredPluginUpdate"
}

Write-Host "服务器已停止，本窗口将在 10 秒后自动关闭..."
Start-Sleep -Seconds 10
