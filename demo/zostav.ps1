<#
.SYNOPSIS
  Builds the configurator layers from the generated variants (vysledky.json):
  - every result is first moved into the base frame (alignment stored by generuj.ps1),
  - variants of the 'podklad' category (wall cladding) become full background images,
  - 'plocha'/'objekt' variants become transparent PNG pieces containing only the pixels
    (inside the category ROI) that differ from the base photo,
  - categories with "naObkladoch" get one set of pieces per wall cladding, from the
    "<variant>@<obklad>" results; the core of the object is restored from the variant's own
    result, so the object is pixel-identical on every cladding,
  - the original shelf accessories are pasted onto every cladding background, after the model
    removed the cladding's own (redrawn) ones ("prazdne-doplnky@<obklad>"),
  - product thumbnails and the data block inside index.html.

.EXAMPLE
  & .\demo\zostav.ps1
  & .\demo\zostav.ps1 -Ladenie C:\temp\ladenie   # also writes masks and sample composites
#>
param(
    [string]$Ladenie
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'spolocne.ps1')
$imgDir = Join-Path $PSScriptRoot 'img'
$results = Read-Results
Write-Host "Layer size: ${W}x$H"

if (Test-Path -LiteralPath $imgDir) { Remove-Item -LiteralPath $imgDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $imgDir | Out-Null
if ($Ladenie) { New-Item -ItemType Directory -Force -Path $Ladenie | Out-Null }

$blurR = Get-Px 2
$base = Get-Input $cfg.podklad
$baseBlur = $base.Rozmaz($blurR)
$base.UlozJpg((Join-Path $imgDir 'povodny.jpg'), 85)

# Category option "stlpec": [x0, x1] = a column (the tap) that stands behind the object;
# above the object's top edge the column is cleared so the tap comes from its own layer.
function Set-ColumnCut($alfa, $own, $kat, [string]$name) {
    if (-not $kat.stlpec) { return }
    $c = [double[]]$kat.stlpec
    $rim = [Mapa]::OrezStlpec($alfa, $own, $W, $H, $c[0], $c[1], 0.015, $kat.roi[1], 0.66, (Get-Px 4))
    if ($rim -lt 0) { Write-Warning "${name}: top edge not found, column not cleared" }
    else { Write-Host "    ${name}: column cleared above y=$rim ($([Math]::Round($rim / $H, 3)))" }
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

$plateCat = $cfg.kategorie | Where-Object { $_.typ -eq 'podklad' } | Select-Object -First 1
$plates = @($cfg.varianty | Where-Object { $_.kategoria -eq $plateCat.id -and $results.Contains($_.id) })
$onPlates = @($cfg.kategorie | Where-Object { $_.naObkladoch })

# Shelf accessories ("doplnky"): the cladding generations redraw (and deform) them, so on every
# cladding background they are replaced by the original ones: the model only removed them from
# the cladding ("<prazdny>@<cladding>"), the originals are pasted onto that, their wall-like
# pixels (edges, shadows, the wall seen through the glass) moved pixel by pixel from the base
# without accessories to this cladding without them. Categories with "bezDoplnkov" leave the
# accessories to the background.
$acc = $null
$accCut = $null
if ($cfg.doplnky -and $results.Contains($cfg.doplnky.prazdny)) {
    $acc = Get-Accessories $results
    $accCut = [Mapa]::Doplnok([Mapa]::Rozmaz($acc.erase, $W, $H, (Get-Px 2)))
    $acc.okolie = [Mapa]::Rozsir($acc.nove, $W, $H, (Get-Px 30))
}

# A cladding result in the base frame, with the original shelf accessories.
function Get-Plate([string]$id) {
    $bareId = "$($cfg.doplnky.prazdny)@$id"
    if (-not $acc -or -not $results.Contains($bareId)) { return Get-Aligned $results $id }
    $plate = Get-Aligned $results $id
    $bare = Get-Aligned $results $bareId $cfg.doplnky
    # The cladding's own copies, sometimes larger than the originals: where it differs from its
    # copy without accessories, near the originals.
    $own = [Mapa]::Prah([Obr]::Rozdiel($plate.Rozmaz((Get-Px 2)), $bare.Rozmaz((Get-Px 2))), 22, 44)
    $own = [Mapa]::Min([Mapa]::Rozsir([Mapa]::Zuz($own, $W, $H, (Get-Px 1)), $W, $H, (Get-Px 5)), $acc.okolie)
    [Mapa]::Oblast($own, $W, $H, [double[]]$cfg.doplnky.roi)
    $alfa = [Mapa]::Rozmaz([Mapa]::Max($acc.erase, [Mapa]::Min($own, $acc.mimo)), $W, $H, (Get-Px 2))
    if ($Ladenie) { [Obr]::ZMasky($alfa, $W, $H).Zmensi(2).UlozJpg((Join-Path $Ladenie "maska-doplnky-$id.jpg"), 80) }
    $bare.Pripocitaj([Obr]::Vyrovnanie($plate, $bare, $alfa, (Get-Px 7), 2000, 14), $alfa)
    $low = $bare.Rozmaz((Get-Px 1))
    $obj = [Obr]::Prefarbi($acc.base, $acc.empty, $low, 25, 55)
    # Inside the outlines from the key, opaque parts coloured like the wall (the soap) still differ
    # from it clearly more than the clear glass does: a lower threshold keeps them.
    if ($acc.kluc) { $obj.Prekry([Obr]::Prefarbi($acc.base, $acc.empty, $low, 18, 32), [Mapa]::Zuz($acc.kluc, $W, $H, (Get-Px 1))) }
    $bare.Prekry($obj, $acc.nove)
    $plate.Prekry($bare, $alfa)
    $plate
}

# Category option "kluc": a helper result with the whole surface painted green. The difference to
# the base misses spots where the old and the new surface have a similar tone (the floor in the
# shadow under the shelf), so the inside of the surface comes from the key, its edges from the
# difference.
function Get-SurfaceMask($img, $kat) {
    $a = Get-Mask $img $kat $baseBlur
    if (-not $kat.kluc -or -not $results.Contains($kat.kluc)) { return , $a }
    $k = (Get-Aligned $results $kat.kluc $kat).Zelena(50, 110)
    [Mapa]::Oblast($k, $W, $H, [double[]]$kat.roi)
    $inner = [Mapa]::Rozmaz([Mapa]::Zuz($k, $W, $H, (Get-Px 2)), $W, $H, (Get-Px 1))
    , [Mapa]::Max([Mapa]::Min($a, [Mapa]::Rozsir($k, $W, $H, (Get-Px 3))), $inner)
}

# Pre-pass for objects placed on every cladding: their result on the original cladding, the
# object alone (difference to the helper image without objects) and the footprint, i.e. the
# union of old and new object positions. On dark tiles the old chrome objects barely differ
# from the wall, so every layer of the category always covers the whole footprint.
$fix = @{}         # variant id -> @{ img; own; core; alfa; kat }
$footprint = @{}   # category id -> mask
foreach ($kat in $onPlates) {
    $ids = @()
    $empty = $null
    if ($kat.prazdny) { $empty = (Get-Aligned $results $kat.prazdny $kat).Rozmaz((Get-Px 1)) }
    foreach ($v in @($cfg.varianty | Where-Object { $_.kategoria -eq $kat.id -and $results.Contains($_.id) })) {
        $img = Get-Aligned $results $v.id $kat
        $nove = Get-NewObject $results $v $kat $img
        # A white object on a white old one barely differs from the base: the object mask is added.
        $own = [Mapa]::Max((Get-Mask $img $kat $baseBlur), $nove)
        # The solid object without its anti-aliased edge, restored unchanged on every cladding.
        # Soft shadows on the wall differ less from the empty wall and are left out: they carry
        # the original wall colour (light patches on dark tiles).
        $solid = $nove
        if ($empty) { $solid = [Mapa]::Min($nove, [Mapa]::Prah([Obr]::Rozdiel($img.Rozmaz((Get-Px 1)), $empty), 45, 75)) }
        $core = [Mapa]::Rozmaz([Mapa]::Zuz([Mapa]::Prah($solid, 0.5, 0.9), $W, $H, (Get-Px 2)), $W, $H, (Get-Px 1))
        $fix[$v.id] = @{ img = $img; own = $own; nove = $nove; core = $core; kat = $kat }
        if ($footprint[$kat.id]) { $footprint[$kat.id] = [Mapa]::Max($footprint[$kat.id], $own) } else { $footprint[$kat.id] = $own }
        $ids += $v.id
        if ($Ladenie) { [Obr]::ZMasky($nove, $W, $H).Zmensi(2).UlozJpg((Join-Path $Ladenie "objekt-$($v.id).jpg"), 80) }
    }
    if (-not $footprint[$kat.id]) { continue }
    $footprint[$kat.id] = [Mapa]::Rozsir($footprint[$kat.id], $W, $H, (Get-Px 2))
    foreach ($id in $ids) {
        # Arrays are assigned directly, never through `$x = if ...`: that would unroll the
        # float[] into object[] and C# would then modify a temporary copy.
        $alfa = [Mapa]::Max($fix[$id].own, $footprint[$kat.id])
        Set-ColumnCut $alfa $fix[$id].nove $kat $id
        if ($kat.bezDoplnkov -and $accCut) { $alfa = [Mapa]::Min($alfa, $accCut) }
        $fix[$id].alfa = $alfa
    }
}

# Objects that surface layers leave out ("bezObjektov"): the floor generation may redraw the
# shower drain, which has its own category; the drain then comes from the layer below.
$cutouts = @{}
foreach ($cid in @($cfg.kategorie | ForEach-Object { $_.bezObjektov } | Where-Object { $_ } | Select-Object -Unique)) {
    $ck = $cfg.kategorie | Where-Object { $_.id -eq $cid }
    $u = $null
    foreach ($v in @($cfg.varianty | Where-Object { $_.kategoria -eq $cid -and $results.Contains($_.id) })) {
        $m = Get-Mask (Get-Aligned $results $v.id $ck) $ck $baseBlur
        if ($u) { $u = [Mapa]::Max($u, $m) } else { $u = $m }
    }
    if ($u) { $cutouts[$cid] = [Mapa]::Doplnok([Mapa]::Rozsir($u, $W, $H, (Get-Px 2))) }
}
function Remove-Cutouts($alfa, $kat) {
    $a = $alfa
    foreach ($cid in @($kat.bezObjektov)) { if ($cid -and $cutouts[$cid]) { $a = [Mapa]::Min($a, $cutouts[$cid]) } }
    , $a
}

$optById = @{}
$kategorie = @()
foreach ($kat in $cfg.kategorie) {
    $n = [double[]]$kat.nahlad
    [Obr]::NacitajVyrez((Join-Path $root $cfg.podklad), $n[0], $n[1], $n[2], $n[3], 320).UlozJpg((Join-Path $imgDir "nahlad-$($kat.id)-povodny.jpg"), 88)
    $moznosti = @([ordered]@{
        id = 'povodny'; nazov = $kat.povodny; kratko = $kat.povodny; detail = $kat.povodnyDetail
        nahlad = "img/nahlad-$($kat.id)-povodny.jpg"
    })
    $roi = [double[]]$kat.roi
    $union = $null

    foreach ($v in @($cfg.varianty | Where-Object { $_.kategoria -eq $kat.id })) {
        if (-not $results.Contains($v.id)) { Write-Warning "No result for $($v.id), skipping"; continue }
        Write-Host "  $($v.id)"

        # Product thumbnails: textures are cropped, products are fitted on white.
        $refs = @()
        for ($i = 0; $i -lt @($v.referencie).Count; $i++) {
            $mode = if ($kat.typ -eq 'objekt') { 2 } else { 1 }
            [Obr]::Nacitaj((Join-Path $root $v.referencie[$i]), 260, 260, $mode).UlozJpg((Join-Path $imgDir "ref-$($v.id)-$i.jpg"), 85)
            $refs += "img/ref-$($v.id)-$i.jpg"
        }

        $opt = [ordered]@{ id = $v.id; nazov = $v.nazov; kratko = $v.kratko; detail = $v.detail; nahlad = $refs[0] }
        if ($kat.typ -eq 'podklad') {
            (Get-Plate $v.id).UlozJpg((Join-Path $imgDir "$($v.id).jpg"), 85)
            $opt.obrazok = "img/$($v.id).jpg"
        } elseif ($kat.naObkladoch) {
            $f = $fix[$v.id]
            $layer = $f.img.Kopia()
            $layer.Pripocitaj([Obr]::Vyrovnanie($base, $layer, $f.alfa, (Get-Px 7), 2000, 14), $f.alfa)
            $layer.Prekry($f.img, $f.core)
            $opt.vrstvy = [ordered]@{ povodny = (Save-Pieces $layer $f.alfa "$($v.id)--povodny" $roi) }
            if ($Ladenie) { [Obr]::ZMasky($f.alfa, $W, $H).Zmensi(2).UlozJpg((Join-Path $Ladenie "maska-$($v.id).jpg"), 80) }
        } else {
            $img = Get-Aligned $results $v.id $kat
            $alfa = Remove-Cutouts (Get-SurfaceMask $img $kat) $kat
            $opt.vrstvy = [ordered]@{ '*' = (Save-Pieces $img $alfa $v.id $roi) }
            if ($union) { $union = [Mapa]::Max($union, $alfa) } else { $union = $alfa }
            if ($Ladenie) { [Obr]::ZMasky($alfa, $W, $H).Zmensi(2).UlozJpg((Join-Path $Ladenie "maska-$($v.id).jpg"), 80) }
        }
        $optById[$v.id] = $opt
        $moznosti += $opt
    }

    # Surfaces get an 'original' layer too, so the base floor wins over a background
    # image in which the model re-rendered the floor slightly differently.
    if ($kat.typ -eq 'plocha' -and $union) {
        $moznosti[0].vrstvy = [ordered]@{ '*' = (Save-Pieces $base $union "$($kat.id)-povodny" $roi) }
    }
    $kategorie += [ordered]@{ id = $kat.id; nazov = $kat.nazov; typ = $kat.typ; z = $kat.z; moznosti = $moznosti }
}

# Per-cladding layers, one cladding at a time (4K images are large).
foreach ($o in $plates) {
    Write-Host "  on $($o.id)"
    $plateImg = Get-Plate $o.id
    foreach ($kat in $onPlates) {
        foreach ($v in @($cfg.varianty | Where-Object { $_.kategoria -eq $kat.id -and $fix.ContainsKey($_.id) })) {
            $key = "$($v.id)@$($o.id)"
            $opt = $optById[$v.id]
            if (-not $results.Contains($key)) {
                Write-Warning "$key has no result, the layer from the original cladding is used"
                $opt.vrstvy[$o.id] = $opt.vrstvy['povodny']
                continue
            }
            $f = $fix[$v.id]
            $img = Get-Aligned $results $key $kat
            # Only the old and new object positions: elsewhere the model may have repainted the
            # wall with a slightly different pattern, which would show as a seam.
            $alfa = [Mapa]::Max($f.nove, $footprint[$kat.id])
            Set-ColumnCut $alfa $f.nove $kat $key
            if ($kat.bezDoplnkov -and $accCut) { $alfa = [Mapa]::Min($alfa, $accCut) }
            # Category option "polica": rows from this y down are the shelf, which is the same on
            # every cladding. The model repaints it unevenly where the old washbasin stood, so it
            # is taken from the variant's own result (and toned to the cladding below).
            if ($kat.polica) { $img.Prekry($f.img, [Mapa]::Riadky($W, $H, [double]$kat.polica, (Get-Px 2))) }
            # The repainted wall and shelf get the tone of the cladding around the layer.
            $img.Pripocitaj([Obr]::Vyrovnanie($plateImg, $img, $alfa, (Get-Px 7), 2000, 14), $alfa)
            # How much the model touched the pasted object (mean difference, 0-255).
            $drift = [Mapa]::Priemer([Obr]::Rozdiel($img, $f.img), $f.core)
            Write-Host ("    {0}: object changed by {1:N1} before restoring it" -f $key, $drift)
            $img.Prekry($f.img, $f.core)
            $opt.vrstvy[$o.id] = Save-Pieces $img $alfa "$($v.id)--$($o.id)" ([double[]]$kat.roi)
        }
    }
    $plateImg = $null
    [GC]::Collect()
}

# --- Data block inside index.html -------------------------------------------------
$credits = @{ '1K' = 6; '2K' = 10; '4K' = 16 }
$data = [ordered]@{
    sirka = $W; vyska = $H
    povodny = 'img/povodny.jpg'
    model = 'gpt-image-2-5-flare-image-to-image'; rozlisenie = $cfg.resolution; kreditovZaObrazok = $credits[$cfg.resolution]
    kategorie = $kategorie
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

# --- Optional sample composites, drawn from the saved pieces exactly like the page ---------
if ($Ladenie) {
    Add-Type -AssemblyName System.Drawing
    $combos = @(
        @('obklad-graphit', 'dlazba-amani', 'baterie-black', 'umyvadlo-okruhle', 'zlab-grafit'),
        @('obklad-calacatta', 'dlazba-graphite', 'baterie-bronze', 'umyvadlo-savoy'),
        @('obklad-graphit', 'baterie-bronze', 'umyvadlo-savoy'),
        @('obklad-travertine', 'dlazba-graphite', 'baterie-black', 'umyvadlo-okruhle'),
        @('baterie-black', 'umyvadlo-okruhle')
    )
    $c = 0
    foreach ($combo in $combos) {
        $c++
        $plateId = @($combo | Where-Object { $_ -like "$($plateCat.id)-*" })[0]
        if (-not $plateId) { $plateId = 'povodny' }
        $plateFile = if ($plateId -eq 'povodny') { 'povodny.jpg' } else { "$plateId.jpg" }
        $src = [System.Drawing.Image]::FromFile((Join-Path $imgDir $plateFile))
        $bmp = New-Object System.Drawing.Bitmap $src
        $src.Dispose()
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        foreach ($kd in @($kategorie | Where-Object { $_.typ -ne 'podklad' } | Sort-Object { $_.z })) {
            $chosen = @($kd.moznosti | Where-Object { $combo -contains $_.id })[0]
            if (-not $chosen) { $chosen = $kd.moznosti[0] }
            if (-not $chosen.vrstvy) { continue }
            $list = $chosen.vrstvy[$plateId]
            if (-not $list) { $list = $chosen.vrstvy['*'] }
            foreach ($p in @($list)) {
                $pi = [System.Drawing.Image]::FromFile((Join-Path $PSScriptRoot $p.src))
                $g.DrawImage($pi, [int]$p.x, [int]$p.y, [int]$p.w, [int]$p.h)
                $pi.Dispose()
            }
        }
        $g.Dispose()
        $bmp.Save((Join-Path $Ladenie "kombinacia-$c.jpg"), [System.Drawing.Imaging.ImageFormat]::Jpeg)
        $bmp.Dispose()
    }
    Write-Host "Debug output in $Ladenie"
}

Write-Host "Done: $((Get-ChildItem $imgDir).Count) files, $([Math]::Round(((Get-ChildItem $imgDir | Measure-Object Length -Sum).Sum) / 1MB, 1)) MB in $imgDir"
