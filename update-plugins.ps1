# ============================================================
#  DeepSeek Harness 插件自动更新脚本
#  由 start-harness.ps1 调用；也可手动运行: powershell -File update-plugins.ps1
#  作用: 检查 @linxin666/dsh-web-ui-all 是否落后于 npm latest，落后则更新
#  日志: 本目录 plugin-update.log（仅在确有动作时追加，避免每次启动刷日志）
# ============================================================
$ErrorActionPreference = 'Continue'
$env:NPM_CONFIG_FETCH_TIMEOUT = '15000'   # 网络检查/下载 15 秒超时，离线时快速失败
$env:NPM_CONFIG_FETCH_RETRIES = '1'

$log = Join-Path $PSScriptRoot 'plugin-update.log'
function Write-Log([string]$m) {
    ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) | Tee-Object -FilePath $log -Append
}

$pkg = '@linxin666/dsh-web-ui-all'
$installedFile = Join-Path $env:USERPROFILE '.dsh\profiles\web\node_modules\@linxin666\dsh-web-ui-all\package.json'

# ---------- 读取当前已安装版本 ----------
$installed = $null
if (Test-Path $installedFile) {
    try { $installed = (Get-Content $installedFile -Raw | ConvertFrom-Json).version } catch {}
}

# ---------- 查询 npm 最新版本 ----------
$latest = $null
try {
    $npmExe = (Get-Command npm -ErrorAction SilentlyContinue).Source
    if ($npmExe) { $latest = (& $npmExe view $pkg version 2>$null | Select-Object -Last 1) }
    if ($latest) { $latest = $latest.ToString().Trim() }
} catch {}
if (-not $latest) { exit 0 }        # 查不到（离线/registry 异常）：静默跳过，不影响启动

# ---------- 版本比较（不降级：latest 更高才更新） ----------
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

if ($installed -and (Compare-SemVer $installed $latest) -ge 0) { exit 0 }   # 已是最新：安静退出

$fromVer = if ($installed) { $installed } else { '(未安装)' }
Write-Log "插件全家桶有新版本: $fromVer -> $latest，开始更新..."

# ---------- 执行更新（优先全局 dsh，其次 npx） ----------
$exitCode = 1
try {
    $dshExe = (Get-Command dsh -ErrorAction SilentlyContinue).Source
    $pre = @()
    if (-not $dshExe) {
        $dshExe = (Get-Command npx -ErrorAction SilentlyContinue).Source
        $pre = @('-y', '@deepseek-ai/dsh')
    }
    if ($dshExe) {
        # 完整输出捕获进日志，便于排查 pnpm 报错
        "== dsh plugin update 输出 $(Get-Date -Format 'HH:mm:ss') ==" | Out-File -FilePath $log -Append
        $out = & $dshExe @pre plugin --profile web update --latest $pkg 2>&1 | Out-String -Width 4096
        $out | Out-File -FilePath $log -Append
        $exitCode = $LASTEXITCODE
    } else {
        Write-Log "未找到 dsh / npx 命令，无法更新"
        exit 1
    }
} catch {
    Write-Log "更新异常: $($_.Exception.Message)"
    exit 1
}

# ---------- 复核结果 ----------
$now = $null
if (Test-Path $installedFile) { try { $now = (Get-Content $installedFile -Raw | ConvertFrom-Json).version } catch {} }
if ($exitCode -eq 0 -and $now -eq $latest) {
    Write-Log "更新成功，当前版本 $now"
    exit 0
} else {
    Write-Log "更新未完成（exit=$exitCode，当前仍为 $now）。若因服务运行占用文件导致，下次启动会自动重试。"
    exit $exitCode
}
