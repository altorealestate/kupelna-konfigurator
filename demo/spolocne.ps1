<#
.SYNOPSIS
  Shared by generuj.ps1 and zostav.ps1 (dot-sourced): configuration, results,
  loading results aligned to the base frame, and masks.
#>

$root = Split-Path $PSScriptRoot -Parent
Add-Type -ReferencedAssemblies System.Drawing -Path (Join-Path $PSScriptRoot 'obrazky.cs')

$cfg = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'varianty.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$resultsPath = Join-Path $PSScriptRoot 'vysledky.json'

# Base frame: every result is aligned to the base image at this size.
$W = [int]$cfg.sirka
$H = [int]$cfg.vyska
# Mask radii were tuned at 1448 px width.
$pxScale = $W / 1448.0
function Get-Px([double]$r) { [int][Math]::Max(1, [Math]::Round($r * $pxScale)) }

# kie.ai credits per generated image (1 credit = $0.005).
$creditsPerImage = @{ '1K' = 6; '2K' = 10; '4K' = 16 }

function Read-Results {
    $results = [ordered]@{}
    if (Test-Path -LiteralPath $resultsPath) {
        $old = Get-Content -LiteralPath $resultsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $old.PSObject.Properties) { $results[$p.Name] = $p.Value }
    }
    $results
}

function Save-Results($results) {
    [IO.File]::WriteAllText($resultsPath, ($results | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false))
}

# An input image (base photo or a prepared input), already in the base frame.
function Get-Input([string]$rel) {
    [Obr]::Nacitaj((Join-Path $root $rel), $W, $H, 0)
}

# A generated result moved into the base frame. With a category, each of its ROI rectangles is
# also shifted to match the result's input locally (the model sometimes moves a part of the
# scene, e.g. the shelf, by a few pixels even when the whole frame matches).
function Get-Aligned($results, [string]$id, $kat) {
    $r = $results[$id]
    if (-not $r) { throw "No result for $id" }
    $img = [Obr]::NacitajZarovnane((Join-Path $root $r.subor), $W, $H, [double[]]$r.zarovnanie)
    if (-not $kat -or -not $kat.roi) { return $img }
    $quads = [double[]]$kat.roi
    $d = [Zarovnanie]::Posuny((Get-Input $r.vstup), $img, $quads, (Get-Px 10))
    if (@($d | Where-Object { $_ -ne 0 }).Count) { Write-Host "    ${id}: local shift $($d -join ' ') px" }
    $img.Posun($quads, $d)
}

# Mask parameters per category type: soft threshold, closing radius, opening radius, grow, feather.
$maskParams = @{
    plocha = @{ t0 = 16; t1 = 40; close = 8; open = 3; grow = 1; blur = 2 }
    objekt = @{ t0 = 14; t1 = 34; close = 4; open = 1; grow = 1; blur = 1 }
}

# Where img differs from the reference (pre-blurred with Rozmaz(Get-Px 2)) inside the category ROI.
function Get-Mask($img, $kat, $refBlur) {
    $p = $maskParams[$kat.typ]
    $a = [Mapa]::Prah([Obr]::Rozdiel($img.Rozmaz((Get-Px 2)), $refBlur), $p.t0, $p.t1)
    $roi = [double[]]$kat.roi
    [Mapa]::Oblast($a, $W, $H, $roi)
    $a = [Mapa]::Zuz([Mapa]::Rozsir($a, $W, $H, (Get-Px $p.close)), $W, $H, (Get-Px $p.close))
    $a = [Mapa]::Rozsir([Mapa]::Zuz($a, $W, $H, (Get-Px $p.open)), $W, $H, (Get-Px $p.open))
    $a = [Mapa]::Rozmaz([Mapa]::Rozsir($a, $W, $H, (Get-Px $p.grow)), $W, $H, (Get-Px $p.blur))
    [Mapa]::Oblast($a, $W, $H, $roi)
    , $a
}

# The new object of variant $v alone (its result $img), without old-object areas that became wall:
# - category with "promptKluc": the model painted the object pure green ("<variant>#kluc"),
#   for objects coloured like the wall behind them (a white washbasin on a light wall),
# - otherwise: where the result differs from the helper image without any object ("prazdny").
function Get-NewObject($results, $v, $kat, $img) {
    $r = Get-Px 1
    if ($kat.promptKluc) {
        $a = (Get-Aligned $results "$($v.id)#kluc" $kat).Zelena(50, 110)
    } else {
        $a = [Mapa]::Prah([Obr]::Rozdiel($img.Rozmaz($r), (Get-Aligned $results $kat.prazdny $kat).Rozmaz($r)), 22, 44)
    }
    $roi = [double[]]$kat.roi
    [Mapa]::Oblast($a, $W, $H, $roi)
    $a = [Mapa]::Rozsir([Mapa]::Zuz($a, $W, $H, $r), $W, $H, $r)                # drop specks
    $a = [Mapa]::Zuz([Mapa]::Rozsir($a, $W, $H, (Get-Px 3)), $W, $H, (Get-Px 3))  # fill holes
    $a = [Mapa]::Rozmaz([Mapa]::Rozsir($a, $W, $H, $r), $W, $H, $r)
    [Mapa]::Oblast($a, $W, $H, $roi)
    , $a
}

# The original objects of a category: the base photo with them painted green ("stary"), or
# where the helper image without objects ("prazdny") differs from the base photo.
function Get-OldObjects($results, $kat) {
    if ($kat.stary) {
        $a = (Get-Aligned $results $kat.stary $kat).Zelena(50, 110)
        [Mapa]::Oblast($a, $W, $H, [double[]]$kat.roi)
        return , [Mapa]::Rozsir($a, $W, $H, (Get-Px 4))
    }
    $base = Get-Input $cfg.podklad
    $a = Get-Mask (Get-Aligned $results $kat.prazdny $kat) $kat $base.Rozmaz((Get-Px 2))
    , [Mapa]::Rozsir($a, $W, $H, (Get-Px 3))
}

# Shelf accessories ("doplnky"), which no option changes but every cladding generation redraws
# (often deformed): the original ones are where the base photo differs from the helper image
# without them ("nove"); clear glass barely differs from the wall seen through it, so the outlines
# of the vase and the bottles come from a copy with them painted green ("kluc"). "erase" adds a
# margin for the cladding's own, sometimes larger copies; "mimo" leaves out the washbasin of
# categories with "bezDoplnkov" (it has its own layers).
function Get-Accessories($results) {
    $acc = $cfg.doplnky
    $base = Get-Input $cfg.podklad
    $nove = Get-NewObject $results $null $acc $base
    $k = $null
    if ($acc.kluc) {
        $k = (Get-Aligned $results $acc.kluc $acc).Zelena(50, 110)
        [Mapa]::Oblast($k, $W, $H, [double[]]$acc.roi)
        $k = [Mapa]::Rozmaz($k, $W, $H, (Get-Px 1))
        $nove = [Mapa]::Max($nove, $k)
    }
    $mimo = [Mapa]::Doplnok((New-Object 'float[]' ($W * $H)))
    foreach ($kat in @($cfg.kategorie | Where-Object { $_.bezDoplnkov })) {
        $mimo = [Mapa]::Min($mimo, [Mapa]::Doplnok((Get-OldObjects $results $kat)))
    }
    $erase = [Mapa]::Min([Mapa]::Rozsir($nove, $W, $H, (Get-Px 12)), $mimo)
    [Mapa]::Oblast($erase, $W, $H, [double[]]$acc.roi)
    @{ base = $base; empty = (Get-Aligned $results $acc.prazdny $acc).Rozmaz((Get-Px 1)); nove = $nove; kluc = $k; erase = [Mapa]::Max($erase, $nove); mimo = $mimo }
}

# Variant option "mierka": the model drew the object too large (the black washbasin mixer, about
# 1.5 times the original one). Inside "roi" the object is scaled by "k" about the point "z" (where
# it stands on the shelf), which moves to "do" (the original mixer's spot). From row "okraj" down
# the washbasin's back rim stands in front of it (straight there; the green key of the basin is
# painted a dozen pixels too high).
# Two masks of the large object: "vysoka" with its shading on the wall (cleared to the background)
# and "tesna", the object alone (pasted scaled; scaled wall around it would show as a lighter box).
function Get-ScaleMask($results, $v, $kat) {
    $roi = [double[]]$v.mierka.roi
    $img = Get-Aligned $results $v.id $kat
    $m = Get-NewObject $results $v $kat $img
    [Mapa]::Oblast($m, $W, $H, $roi)
    $t = [Mapa]::Prah([Obr]::Rozdiel($img.Rozmaz(1), (Get-Aligned $results $kat.prazdny $kat).Rozmaz(1)), 40, 80)
    [Mapa]::Oblast($t, $W, $H, $roi)
    $t = [Mapa]::Zuz([Mapa]::Rozsir($t, $W, $H, (Get-Px 1)), $W, $H, (Get-Px 1))   # highlights inside
    $t = [Mapa]::Rozsir([Mapa]::Zuz($t, $W, $H, 1), $W, $H, 1)                     # specks
    @{ vysoka = [Mapa]::Rozmaz([Mapa]::Rozsir($m, $W, $H, (Get-Px 2)), $W, $H, 1); tesna = [Mapa]::Rozmaz($t, $W, $H, 1) }
}
# The freed wall is the helper image without objects ("prazdny") moved to the wall colour of $img
# around the object: a cladding result still has the original mixer, a few pixels off on some.
function Set-Scale($results, $img, $v, $kat, $masks) {
    $s = $v.mierka
    $z = [double[]]$s.z
    $d = [double[]]$s.do
    $t = ($z[0] * $W), ($z[1] * $H), ($d[0] * $W), ($d[1] * $H), [double]$s.k
    $scaled = $img.Mierka($t[0], $t[1], $t[2], $t[3], $t[4])
    $small = [Mapa]::Mierka($masks.tesna, $W, $H, $t[0], $t[1], $t[2], $t[3], $t[4])
    $front = [Mapa]::Riadky($W, $H, [double]$s.okraj, 2)
    $small = [Mapa]::Min($small, [Mapa]::Doplnok($front))
    $empty = Get-Aligned $results $kat.prazdny $kat
    $keep = [Mapa]::Doplnok([Mapa]::Max([Mapa]::Rozsir($masks.vysoka, $W, $H, (Get-Px 3)), $front))
    $bg = [Obr]::Prefarbi($empty, $empty.RozmazVazene($keep, (Get-Px 25)), $img.RozmazVazene($keep, (Get-Px 25)), 1000, 1001)
    # The large mixer's foot reached over the back rim of the washbasin, which is the same on
    # every cladding: there the helper image is used as it is.
    $img.Prekry($empty, [Mapa]::Min($masks.vysoka, $front))
    $img.Prekry($bg, [Mapa]::Min($masks.vysoka, [Mapa]::Doplnok($front)))
    $img.Prekry($scaled, $small)
}

# Helper results a per-cladding task of variant $v needs besides the variant and the cladding.
function Get-ObjectDeps($v, $kat) {
    if ($kat.promptKluc) { "$($v.id)#kluc" } else { $kat.prazdny }
    if ($kat.stary) { $kat.stary }
}
