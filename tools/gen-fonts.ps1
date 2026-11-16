# Rasterises the TTFs in tools\fonts-src into BMFont (.fnt + .png) bitmap fonts for Connect IQ.
# Every font is laid out so that the top of the capitals sits $pad pixels below the draw position.
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'

$out = Join-Path (Split-Path $PSScriptRoot) 'resources\fonts'
New-Item -ItemType Directory -Force $out | Out-Null

$pfc = New-Object System.Drawing.Text.PrivateFontCollection
Get-ChildItem "$PSScriptRoot\fonts-src\*.ttf" | ForEach-Object { $pfc.AddFontFile($_.FullName) }
$fmt = [System.Drawing.StringFormat]::GenericTypographic
$pad = 2

# $xScale < 1 condenses the glyphs horizontally
function MakeFont($name, $familyName, $cap, [string]$chars, $track, $xScale = 1.0) {
    $fam = $pfc.Families | Where-Object Name -like "$familyName*" | Select-Object -First 1
    if (-not $fam) { throw "Font family '$familyName' not found" }
    $style = if ($fam.IsStyleAvailable([System.Drawing.FontStyle]::Regular)) { 0 } else { 1 }
    $mk = {
        param($ch)
        $p = New-Object System.Drawing.Drawing2D.GraphicsPath
        $p.AddString([string]$ch, $fam, $style, 200, (New-Object System.Drawing.PointF 0, 0), $fmt)
        $p
    }
    $ref = (& $mk 'H').GetBounds()
    $s = $cap / $ref.Height
    $sx = $s * $xScale
    $lineHeight = $cap + 2 * $pad

    # digits share one advance so values don't jump around
    $digitW = 0
    foreach ($d in '0123456789'.ToCharArray()) { $w = [math]::Ceiling((& $mk $d).GetBounds().Width * $sx); if ($w -gt $digitW) { $digitW = $w } }

    $glyphs = @(); $x = 2; $y = 0; $rowH = 0; $atlasW = 256
    foreach ($ch in $chars.ToCharArray()) {
        if ($ch -eq ' ') { $glyphs += [pscustomobject]@{ Id = 32; X = 0; Y = 0; W = 1; H = 1; XOff = 0; YOff = 0; Adv = [int][math]::Round($cap * 0.32); Path = $null; DX = 0; DY = 0 }; continue }
        $p = & $mk $ch; $b = $p.GetBounds()
        $w = [int][math]::Ceiling($b.Width * $sx)
        $topExact = ($b.Y - $ref.Y) * $s + $pad
        $yOff = [int][math]::Floor($topExact) - 1
        $frac = $topExact - [math]::Floor($topExact)
        $gw = $w + 2; $gh = [int][math]::Ceiling($b.Height * $s + $frac) + 2
        if ($yOff -lt 0) { $yOff = 0 }
        if ($yOff + $gh -gt $lineHeight) { $gh = $lineHeight - $yOff }
        if ($x + $gw + 1 -gt $atlasW) { $x = 0; $y += $rowH + 1; $rowH = 0 }
        if ([char]::IsDigit($ch)) { $xOff = [int][math]::Floor(($digitW - $w) / 2); $adv = $digitW + $track } else { $xOff = 0; $adv = $w + $track }
        $glyphs += [pscustomobject]@{ Id = [int]$ch; X = $x; Y = $y; W = $gw; H = $gh; XOff = $xOff; YOff = $yOff; Adv = $adv; Path = $p
            DX = $x + 1 - $b.X * $sx; DY = $y + 1 + $frac - $b.Y * $s }
        $x += $gw + 1; if ($gh -gt $rowH) { $rowH = $gh }
    }
    $atlasH = $y + $rowH + 1

    $bmp = New-Object System.Drawing.Bitmap $atlasW, $atlasH, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.PixelOffsetMode = 'HighQuality'
    $g.Clear([System.Drawing.Color]::Transparent)
    foreach ($gl in $glyphs) {
        if (-not $gl.Path) { continue }
        $m = New-Object System.Drawing.Drawing2D.Matrix
        $m.Translate([single]$gl.DX, [single]$gl.DY); $m.Scale([single]$sx, [single]$s)
        $gl.Path.Transform($m)
        $g.SetClip((New-Object System.Drawing.Rectangle $gl.X, $gl.Y, $gl.W, $gl.H))
        $g.FillPath([System.Drawing.Brushes]::White, $gl.Path)
    }
    $g.Dispose()
    $bmp.Save("$out\$name.png", [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()

    $lines = @(
        "info face=`"$familyName`" size=$cap bold=0 italic=0 charset=`"`" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1 outline=0"
        "common lineHeight=$lineHeight base=$($cap + $pad) scaleW=$atlasW scaleH=$atlasH pages=1 packed=0 alphaChnl=1 redChnl=0 greenChnl=0 blueChnl=0"
        "page id=0 file=`"$name.png`""
        "chars count=$($glyphs.Count)"
    )
    foreach ($gl in $glyphs) { $lines += "char id=$($gl.Id) x=$($gl.X) y=$($gl.Y) width=$($gl.W) height=$($gl.H) xoffset=$($gl.XOff) yoffset=$($gl.YOff) xadvance=$($gl.Adv) page=0 chnl=15" }
    Set-Content "$out\$name.fnt" $lines -Encoding ascii
    "{0,-6} cap={1,-3} atlas={2}x{3} digitAdvance={4}" -f $name, $cap, $atlasW, $atlasH, ($digitW + $track)
}

$caps = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ%.-:+/ ' + [char]0xB0
MakeFont 'time'  'Saira Stencil One' 52 '0123456789:' 3
MakeFont 'value' 'Saira Stencil One' 16 $caps 1 0.88
MakeFont 'date'  'Saira Stencil One' 13 $caps 1
MakeFont 'label' 'Saira Condensed'    9 $caps 1
