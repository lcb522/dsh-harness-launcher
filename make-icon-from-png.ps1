# 将 PNG 图片转换为多尺寸 .ico 图标
# 用法: pwsh -File make-icon-from-png.ps1 [源PNG] [输出ICO]
param(
    [string]$SourcePng = 'C:\Users\lcbin\OneDrive\图片\deepseek-color.png',
    [string]$OutIco    = 'C:\Users\lcbin\Desktop\DeepSeek workSpace\launcher\deepseek-color.ico'
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# 复制一份源图到 launcher 目录（避免依赖 OneDrive 同步状态）
$localCopy = Join-Path $PSScriptRoot 'deepseek-color.png'
Copy-Item -LiteralPath $SourcePng -Destination $localCopy -Force
"源图: $SourcePng -> $localCopy"

$src = [System.Drawing.Image]::FromFile($localCopy)
"源尺寸: $($src.Width)x$($src.Height)"

# 先在 1024 画布上高质量缩放到 256，再逐级缩小（两级缩放比一步到位更平滑）
$big = New-Object System.Drawing.Bitmap 1024, 1024
$g0 = [System.Drawing.Graphics]::FromImage($big)
$g0.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g0.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g0.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g0.DrawImage($src, 0, 0, 1024, 1024)
$g0.Dispose()
$src.Dispose()

$base256 = New-Object System.Drawing.Bitmap 256, 256
$g1 = [System.Drawing.Graphics]::FromImage($base256)
$g1.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g1.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g1.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g1.DrawImage($big, 0, 0, 256, 256)
$g1.Dispose()
$big.Dispose()

# 生成各尺寸并内嵌 PNG
$sizes = @(256, 64, 48, 32, 16)
$pngBytes = @{}
foreach ($s in $sizes) {
    $b = New-Object System.Drawing.Bitmap $s, $s
    $g = [System.Drawing.Graphics]::FromImage($b)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.DrawImage($base256, 0, 0, $s, $s)
    $g.Dispose()
    $ms = New-Object System.IO.MemoryStream
    $b.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $b.Dispose()
    $pngBytes[$s] = $ms.ToArray()
}
$base256.Dispose()

# 组装 ICO 容器
$fs = [System.IO.File]::Create($OutIco)
$bw = New-Object System.IO.BinaryWriter($fs)
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $s = $sizes[$i]
    $dim = if ($s -ge 256) { [byte]0 } else { [byte]$s }
    $bw.Write($dim); $bw.Write($dim)
    $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32)
    $bw.Write([uint32]$pngBytes[$s].Length)
    $bw.Write([uint32]$offset)
    $offset += $pngBytes[$s].Length
}
foreach ($s in $sizes) { $bw.Write($pngBytes[$s]) }
$bw.Flush(); $bw.Close(); $fs.Close()

$icoFile = Get-Item $OutIco
"ICO: $($icoFile.FullName) ($($icoFile.Length) bytes)"
"包含尺寸: $($sizes -join ', ')"
