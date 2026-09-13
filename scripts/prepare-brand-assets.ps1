param(
    [Parameter(Mandatory=$true)][string]$LogoPath,
    [Parameter(Mandatory=$true)][string]$GroupQRPath
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$taskAssets = Join-Path (Split-Path $PSScriptRoot -Parent) 'PelicanSaveEditor/Assets.xcassets'
$taskLogoSet = Join-Path $taskAssets 'AppLogo.imageset'
$taskQRSet = Join-Path $taskAssets 'QQGroupQRCode.imageset'
New-Item -ItemType Directory -Force -Path $taskLogoSet,$taskQRSet | Out-Null
Copy-Item -LiteralPath $LogoPath -Destination (Join-Path $taskLogoSet 'prismatic-shard.png')
Copy-Item -LiteralPath $GroupQRPath -Destination (Join-Path $taskQRSet 'qq-group-719471525.jpg')
@{images=@(@{filename='prismatic-shard.png';idiom='universal'});info=@{author='xcode';version=1}} | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 (Join-Path $taskLogoSet 'Contents.json')
@{images=@(@{filename='qq-group-719471525.jpg';idiom='universal'});info=@{author='xcode';version=1}} | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 (Join-Path $taskQRSet 'Contents.json')
$taskSource = [System.Drawing.Bitmap]::FromFile($LogoPath)
$taskIcon = [System.Drawing.Bitmap]::new(1024,1024,[System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$taskGraphics = [System.Drawing.Graphics]::FromImage($taskIcon)
try {
    # Exact supplied pixels, integer scaling, and an opaque iOS icon background.
    $taskGraphics.Clear([System.Drawing.Color]::FromArgb(255,247,225))
    $taskGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $taskGraphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $taskScale = [Math]::Floor(768 / [Math]::Max($taskSource.Width, $taskSource.Height))
    $taskWidth = $taskSource.Width * $taskScale
    $taskHeight = $taskSource.Height * $taskScale
    $taskRectangle = [System.Drawing.Rectangle]::new((1024-$taskWidth)/2,(1024-$taskHeight)/2,$taskWidth,$taskHeight)
    $taskGraphics.DrawImage($taskSource,$taskRectangle,0,0,$taskSource.Width,$taskSource.Height,[System.Drawing.GraphicsUnit]::Pixel)
    $taskIcon.Save((Join-Path $taskAssets 'AppIcon.appiconset/AppIcon-1024.png'),[System.Drawing.Imaging.ImageFormat]::Png)
} finally {
    $taskGraphics.Dispose()
    $taskIcon.Dispose()
    $taskSource.Dispose()
}
Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $taskLogoSet 'prismatic-shard.png'),(Join-Path $taskQRSet 'qq-group-719471525.jpg'),(Join-Path $taskAssets 'AppIcon.appiconset/AppIcon-1024.png') | Select-Object Hash,Path
