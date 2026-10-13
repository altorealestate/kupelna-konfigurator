<#
.SYNOPSIS
  Builds the configurator layers from the generated variants (vysledky.json):
  - variants of the 'podklad' category (wall cladding) become full background images,
  - 'plocha'/'objekt' variants become transparent PNG pieces containing only the
    pixels (inside the category ROI) that differ from the base photo,
  - objects marked "prefarbit" get one set of pieces per background, with the wall
    around the object shifted to that background's colour (no light halo on dark tiles),
  - product thumbnails, test gallery images, and the data block inside index.html.

.EXAMPLE
  & .\demo\zostav.ps1
  & .\demo\zostav.ps1 -Ladenie C:\temp\ladenie   # also writes mask previews and sample composites
#>
param(
    [string]$Ladenie
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$imgDir = Join-Path $PSScriptRoot 'img'
Add-Type -ReferencedAssemblies System.Drawing -Path (Join-Path $PSScriptRoot 'obrazky.cs')

$cfg = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'varianty.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$res = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'vysledky.json') -Raw -Encoding UTF8 | ConvertFrom-Json

# Common size = size of the first result; other outputs are resized to it.
$first = $res.PSObject.Properties | Select-Object -First 1
$size = [Obr]::VelkostSuboru((Join-Path $root $first.Value.subor))
$W = $size.Width; $H = $size.Height
Write-Host "Layer size: ${W}x$H"

if (Test-Path -LiteralPath $imgDir) { Remove-Item -LiteralPath $imgDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $imgDir | Out-Null
if ($Ladenie) { New-Item -ItemType Directory -Force -Path $Ladenie | Out-Null }

$LowRadius = 10
$base = [Obr]::Nacitaj((Join-Path $root $cfg.podklad), $W, $H, 0)
$baseBlur = $base.Rozmaz(2)
$base.UlozJpg((Join-Path $imgDir 'povodny.jpg'), 86)

# Mask parameters per category type: soft threshold, closing radius, opening radius, grow, feather.
$params = @{
    plocha = @{ t0 = 16; t1 = 40; close = 8; open = 3; grow = 1; blur = 2 }
    objekt = @{ t0 = 14; t1 = 34; close = 4; open = 1; grow = 1; blur = 1 }
}

function Get-Mask($img, $kat) {
    $p = $params[$kat.typ]
    $a = [Mapa]::Prah([Obr]::Rozdiel($img.Rozmaz(2), $baseBlur), $p.t0, $p.t1)
    $roi = [double[]]$kat.roi
    [Mapa]::Oblast($a, $W, $H, $roi)
    $a = [Mapa]::Zuz([Mapa]::Rozsir($a, $W, $H, $p.close), $W, $H, $p.close)
    $a = [Mapa]::Rozsir([Mapa]::Zuz($a, $W, $H, $p.open), $W, $H, $p.open)
    $a = [Mapa]::Rozmaz([Mapa]::Rozsir($a, $W, $H, $p.grow), $W, $H, $p.blur)
    [Mapa]::Oblast($a, $W, $H, $roi)
    , $a
}

# Saves one cropped PNG per ROI rectangle (keeps files small when the ROI is scattered).
function Save-Pieces($img, $alfa, [string]$name, [double[]]$roi) {
    $pieces = @()
    for ($q = 0; $q -lt $roi.Count; $q += 4) {
        $a = [float[]]$alfa.Clone()
        [Mapa]::Oblast($a, $W, $H, [double[]]$roi[$q..($q + 3)])
        $bb = [Mapa]::Ohranicenie($a, $W, $H, 0.004, 2)
        if ($bb[2] -eq 0) { continue }
        $file = "$name-$($q / 4).png"
        $img.UlozPng((Join-Path $imgDir $file), $a, $bb[0], $bb[1], $bb[2], $bb[3])
        $pieces += [ordered]@{ src = "img/$file"; x = $bb[0]; y = $bb[1]; w = $bb[2]; h = $bb[3] }
    }
    if ($pieces.Count -eq 0) { Write-Warning "Layer $name is empty" }
    , $pieces
}

function Get-Result($v) {
    $r = $res.($v.id)
    if (-not $r) { return $null }
    [Obr]::Nacitaj((Join-Path $root $r.subor), $W, $H, 0)
}

# Pre-pass: masks of the recoloured objects. Their union (old and new object positions)
# is left out when estimating the wall colour, so the objects do not tint the estimate.
$loaded = @{}   # variant id -> @{ img; alfa; kat }
$objects = New-Object 'float[]' ($W * $H)
foreach ($kat in @($cfg.kategorie | Where-Object { $_.prefarbit })) {
    foreach ($v in @($cfg.varianty | Where-Object { $_.kategoria -eq $kat.id })) {
        $img = Get-Result $v
        if (-not $img) { continue }
        $alfa = Get-Mask $img $kat
        $loaded[$v.id] = @{ img = $img; alfa = $alfa; kat = $kat }
        $objects = [Mapa]::Max($objects, $alfa)
    }
}
$wallWeight = [Mapa]::Doplnok([Mapa]::Rozsir($objects, $W, $H, 4))
$baseLow = $base.RozmazVazene($wallWeight, $LowRadius)

$plates = @([ordered]@{ id = 'povodny'; img = $base; low = $baseLow })
$kategorie = @()
$testy = @()
foreach ($kat in $cfg.kategorie) {
    $n = [double[]]$kat.nahlad
    $base.Vyrez($n[0], $n[1], $n[2], $n[3]).UlozJpg((Join-Path $imgDir "nahlad-$($kat.id)-povodny.jpg"), 85)
    $moznosti = @([ordered]@{
        id = 'povodny'; nazov = $kat.povodny; kratko = $kat.povodny; detail = $kat.povodnyDetail
        nahlad = "img/nahlad-$($kat.id)-povodny.jpg"
    })
    $union = $null

    foreach ($v in @($cfg.varianty | Where-Object { $_.kategoria -eq $kat.id })) {
        $r = $res.($v.id)
        if (-not $r) { Write-Warning "No result for $($v.id), skipping"; continue }
        Write-Host "  $($v.id)"
        $img = if ($loaded.ContainsKey($v.id)) { $loaded[$v.id].img } else { Get-Result $v }
        $img.UlozJpg((Join-Path $imgDir "$($v.id).jpg"), 84)

        # Product thumbnails: textures are cropped, products are fitted on white.
        $refs = @()
        for ($i = 0; $i -lt @($v.referencie).Count; $i++) {
            $mode = if ($kat.typ -eq 'objekt') { 2 } else { 1 }
            [Obr]::Nacitaj((Join-Path $root $v.referencie[$i]), 260, 260, $mode).UlozJpg((Join-Path $imgDir "ref-$($v.id)-$i.jpg"), 85)
            $refs += "img/ref-$($v.id)-$i.jpg"
        }

        $opt = [ordered]@{ id = $v.id; nazov = $v.nazov; kratko = $v.kratko; detail = $v.detail; nahlad = $refs[0] }
        if ($kat.typ -eq 'podklad') {
            $opt.obrazok = "img/$($v.id).jpg"
            $plates += [ordered]@{ id = $v.id; img = $img; low = $img.RozmazVazene($wallWeight, $LowRadius) }
        } else {
            $alfa = if ($loaded.ContainsKey($v.id)) { $loaded[$v.id].alfa } else { Get-Mask $img $kat }
            $roi = [double[]]$kat.roi
            $vrstvy = [ordered]@{}
            if ($kat.prefarbit) {
                foreach ($pl in $plates) {
                    $layer = if ($pl.id -eq 'povodny') { $img } else { [Obr]::Prefarbi($img, $baseLow, $pl.low, 25, 55) }
                    $vrstvy[$pl.id] = Save-Pieces $layer $alfa "$($v.id)--$($pl.id)" $roi
                }
            } else {
                $vrstvy['*'] = Save-Pieces $img $alfa $v.id $roi
            }
            $opt.vrstvy = $vrstvy
            $loaded[$v.id] = @{ img = $img; alfa = $alfa; kat = $kat }
            $union = if ($union) { [Mapa]::Max($union, $alfa) } else { $alfa }
            if ($Ladenie) { [Obr]::ZMasky($alfa, $W, $H).UlozJpg((Join-Path $Ladenie "maska-$($v.id).jpg"), 80) }
        }
        $moznosti += $opt
        $testy += [ordered]@{
            id = $v.id; kategoriaId = $kat.id; kategoria = $kat.nazov; nazov = $v.nazov; kratko = $v.kratko; detail = $v.detail
            obrazok = "img/$($v.id).jpg"; referencie = $refs; sekund = $r.sekund; taskId = $r.taskId
        }
    }

    # Surfaces get an 'original' layer too, so the base floor wins over a background
    # image in which the model re-rendered the floor slightly differently.
    if ($kat.typ -eq 'plocha' -and $union) {
        $moznosti[0].vrstvy = [ordered]@{ '*' = (Save-Pieces $base $union "$($kat.id)-povodny" ([double[]]$kat.roi)) }
        $loaded["$($kat.id)-povodny"] = @{ img = $base; alfa = $union; kat = $kat }
    }
    $kategorie += [ordered]@{ id = $kat.id; nazov = $kat.nazov; typ = $kat.typ; z = $kat.z; moznosti = $moznosti }
}

# --- Data block inside index.html -------------------------------------------------
$data = [ordered]@{
    sirka = $W; vyska = $H
    povodny = 'img/povodny.jpg'
    model = 'gpt-image-2-5-flare-image-to-image'; rozlisenie = $cfg.resolution; kreditovZaObrazok = 6
    kategorie = $kategorie
    testy = $testy
}
$json = $data | ConvertTo-Json -Depth 10 -Compress
$indexPath = Join-Path $PSScriptRoot 'index.html'
if (Test-Path -LiteralPath $indexPath) {
    $html = [IO.File]::ReadAllText($indexPath, [Text.Encoding]::UTF8)
    $pattern = '(?s)(/\*DATA\*/).*?(/\*/DATA\*/)'
    if ($html -notmatch $pattern) { throw 'index.html has no /*DATA*/ ... /*/DATA*/ block.' }
    $html = [regex]::Replace($html, $pattern, { param($m) $m.Groups[1].Value + "window.KUPELNA = $json;" + $m.Groups[2].Value })
    [IO.File]::WriteAllText($indexPath, $html, (New-Object Text.UTF8Encoding $false))
    Write-Host 'index.html data updated.'
}

# --- Optional sample composites for checking (same logic as the page) --------------
if ($Ladenie) {
    $combos = @(
        @('obklad-graphit', 'dlazba-amani', 'baterie-black', 'umyvadlo-okruhle', 'zlab-grafit'),
        @('obklad-calacatta', 'dlazba-graphite', 'baterie-bronze', 'umyvadlo-savoy'),
        @('obklad-graphit', 'baterie-bronze', 'umyvadlo-savoy'),
        @('obklad-travertine', 'dlazba-graphite', 'baterie-black', 'umyvadlo-okruhle')
    )
    $c = 0
    foreach ($combo in $combos) {
        $c++
        $plate = $plates | Where-Object { $combo -contains $_.id } | Select-Object -First 1
        if (-not $plate) { $plate = $plates[0] }
        $comp = $plate.img.Kopia()
        $ids = @($combo | Where-Object { $loaded.ContainsKey($_) })
        if (-not ($combo | Where-Object { $_ -like 'dlazba-*' })) { $ids += 'dlazba-povodny' }
        foreach ($id in $ids | Sort-Object { $loaded[$_].kat.z }) {
            $l = $loaded[$id]
            $layer = if ($l.kat.prefarbit -and $plate.id -ne 'povodny') { [Obr]::Prefarbi($l.img, $baseLow, $plate.low, 25, 55) } else { $l.img }
            $comp.Prekry($layer, $l.alfa)
        }
        $comp.UlozJpg((Join-Path $Ladenie "kombinacia-$c.jpg"), 88)
    }
    Write-Host "Debug output in $Ladenie"
}

Write-Host "Done: $((Get-ChildItem $imgDir).Count) files, $([Math]::Round(((Get-ChildItem $imgDir | Measure-Object Length -Sum).Sum) / 1MB, 1)) MB in $imgDir"
