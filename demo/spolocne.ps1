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

# Helper results a per-cladding task of variant $v needs besides the variant and the cladding.
function Get-ObjectDeps($v, $kat) {
    if ($kat.promptKluc) { "$($v.id)#kluc" } else { $kat.prazdny }
    if ($kat.stary) { $kat.stary }
}
