<#
.SYNOPSIS
  New approach (demo2): products independent of the wall cladding. Builds demo2\img and the data
  in demo2\index.html from the same results as zostav.ps1 ("nezavisle" in varianty.json):
  - every cladding is one generation on the empty scene ("<prazdna>@<obklad>"); the original
    cladding is the base photo with the empty scene where the objects and their shadows were,
  - every product of a category with "naObkladoch", the original ones too, is ONE layer cut out
    of its own generation along its green key: the edge colour is moved off the wall it was
    generated on (estimated from that generation) and the shadow (darkening against that wall)
    is part of the layer, so the same layer fits every cladding,
  - the shelf accessories are pasted into every cladding image (as in zostav.ps1),
  - floor, drain, thumbnails and the previous approach (for the comparison switch on the page)
    come from the data in demo\index.html: run zostav.ps1 first.

.EXAMPLE
  & .\demo\zostav2.ps1
  & .\demo\zostav2.ps1 -Ladenie C:\temp\ladenie2   # also masks and sample composites
#>
param(
    [string]$Ladenie
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'spolocne.ps1')
$results = Read-Results
$n = $cfg.nezavisle
if (-not $results.Contains($n.prazdna)) { throw "No result for $($n.prazdna): generuj.ps1 -Ids $($n.prazdna)" }
$outDir = Join-Path $root 'demo2'
$imgDir = Join-Path $outDir 'img'
if (Test-Path -LiteralPath $imgDir) { Remove-Item -LiteralPath $imgDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $imgDir | Out-Null
if ($Ladenie) { New-Item -ItemType Directory -Force -Path $Ladenie | Out-Null }
Write-Host "Layer size: ${W}x$H"

$base = Get-Input $cfg.podklad
$empty = Get-Aligned $results $n.prazdna
$R = Get-Px ([double]$n.tien)
$ones = [Mapa]::Doplnok((New-Object 'float[]' ($W * $H)))

function Save-Mask($m, [string]$name) {
    if ($Ladenie) { [Obr]::ZMasky($m, $W, $H).Zmensi(2).UlozJpg((Join-Path $Ladenie "$name.jpg"), 80) }
}

# The union of the normalised rectangles q, each grown by $grow pixels.
function Get-Rects([double[]]$q, [double]$grow) {
    $g = [double[]]@(for ($i = 0; $i -lt $q.Count; $i += 4) { $q[$i] - $grow / $W; $q[$i + 1] - $grow / $H; $q[$i + 2] + $grow / $W; $q[$i + 3] + $grow / $H })
    $m = [float[]]$ones.Clone()
    [Mapa]::Oblast($m, $W, $H, $g)
    , $m
}

# The empty scene toned to img outside zone (the object with its shadow): img's own background.
function Get-Background($img, $zone) {
    $b = $empty.Kopia()
    $b.Pripocitaj([Obr]::Vyrovnanie($img, $b, $zone, (Get-Px 7), 2000, 14), $ones)
    $b
}

# Where img differs from its background (soft threshold t0..t1, 1 px blur) inside the rectangles
# q, without specks and holes; the background is toned to img outside zone0.
function Get-Difference($img, $zone0, [double[]]$q, [float]$t0, [float]$t1) {
    $bg = Get-Background $img $zone0
    $r = Get-Px 1
    $a = [Mapa]::Prah([Obr]::Rozdiel($img.Rozmaz($r), $bg.Rozmaz($r)), $t0, $t1)
    [Mapa]::Oblast($a, $W, $H, $q)
    $a = [Mapa]::Rozsir([Mapa]::Zuz($a, $W, $H, $r), $W, $H, $r)
    $a = [Mapa]::Zuz([Mapa]::Rozsir($a, $W, $H, (Get-Px 3)), $W, $H, (Get-Px 3))
    , $a
}

# One layer of the object in img (rectangles q): outline = where it may be (soft), tight = surely
# the object (from a key; $null: far from img's own wall and of the object's colour). Inside the
# outline the opacity is how far a pixel lies between the wall right around the object in img
# itself and the object's own colour next to it (a threshold on the difference to the empty
# scene, another generation, let the warmer wall of the black taps' generation through as a
# halo). "mimo" = 0 where other objects of img are. The shadow reaches $R px around the outline.
# Returns @{ img; alfa; zone } (and masks for -Ladenie).
function New-Layer($img, $outline, $tight, [double[]]$q, $mimo) {
    # Where the original objects with their shadows are (the original cladding gets the empty
    # scene there).
    $zone = [Mapa]::Rozsir([Mapa]::Prah($outline, 0.01, 0.02), $W, $H, 2 * $R)
    # The wall of img itself (the empty scene is another generation: its wall differs in tone,
    # warmer on the black taps' generation, and in the joints). First estimated from around the
    # outline with a large radius, then the pixels inside the outline that match it are added
    # (the wall between a riser and its hose, around a large thermostat).
    $r = Get-Px 1
    $c1 = $img.Rozmaz($r)
    $region = [Mapa]::Prah($outline, 0.01, 0.05)
    $wgt = [Mapa]::Min([Mapa]::Doplnok([Mapa]::Rozsir($region, $W, $H, (Get-Px 2))), $mimo)
    # Also background: what matches the empty scene toned to img (it has the bathtub rim, the
    # shelf's edges and the joints, the wall estimate only knows the wall), a few pixels off at
    # most (another generation draws them a little elsewhere).
    $scene = [Vrstva]::RozdielPosun($c1, (Get-Background $img ([Mapa]::Max($zone, [Mapa]::Doplnok($mimo)))).Rozmaz($r), (Get-Px 4), (Get-Px 1))
    # The first radius must reach real wall from anywhere inside the outline (a smaller one blends
    # in the object, its dark parts then pass as wall).
    foreach ($rad in @((Get-Px 60), (Get-Px 15))) {
        $res = [Mapa]::Min([Obr]::Rozdiel($c1, $img.RozmazVazene($wgt, $rad)), $scene)
        $like = [Mapa]::Doplnok([Mapa]::Rozsir([Mapa]::Prah($res, 25, 45), $W, $H, $r))
        $wgt = [Mapa]::Min([Mapa]::Max($wgt, [Mapa]::Min($like, $region)), $mimo)
    }
    if ($null -eq $tight) {
        $tight = [Mapa]::Min($outline, [Mapa]::Prah([Obr]::Rozdiel($c1, $img.RozmazVazene($wgt, (Get-Px 8))), 50, 80))
        # ...and of the object's colour: a dark contact shadow the model drew next to it (brown on
        # the bathtub rim) is a mix of the object's colour and the wall, so it stays translucent.
        $sure = [Mapa]::Rozsir([Mapa]::Prah($tight, 0.2, 0.4), $W, $H, (Get-Px 2))
        $core = [Mapa]::Zuz([Mapa]::Prah($tight, 0.5, 0.9), $W, $H, (Get-Px 1))
        $p = [Vrstva]::Alfa($c1, $img.RozmazVazene([Mapa]::Min($wgt, [Mapa]::Doplnok($sure)), (Get-Px 8)), $img.RozmazVazene($core, (Get-Px 12)), $ones, 24)
        $tight = [Mapa]::Min($tight, [Mapa]::Prah($p, 0.75, 0.9))
    }
    $sure = [Mapa]::Rozsir([Mapa]::Prah($tight, 0.2, 0.4), $W, $H, (Get-Px 2))
    $wall = $img.RozmazVazene([Mapa]::Min($wgt, [Mapa]::Doplnok($sure)), (Get-Px 8))
    # For the shadow: the wall beyond its reach.
    $bg = $img.RozmazVazene([Mapa]::Min($wgt, [Mapa]::Doplnok([Mapa]::Rozsir($sure, $W, $H, $R))), (Get-Px 30))
    $core = [Mapa]::Zuz([Mapa]::Prah($tight, 0.5, 0.9), $W, $H, (Get-Px 1))
    # The object's own colour next to an edge (far enough that a faint halo pixel still finds it).
    $obj = $img.RozmazVazene($core, (Get-Px 12))
    $a = [Mapa]::Max($core, [Vrstva]::Alfa($img.Rozmaz(1), $wall, $obj, $outline, 24))
    $tien = [Mapa]::Rozmaz([Mapa]::Rozsir([Mapa]::Prah($outline, 0.3, 0.6), $W, $H, $R), $W, $H, [Math]::Max(1, [int]($R / 3)))
    $tien = [Mapa]::Min([Mapa]::Min($tien, (Get-Rects $q $R)), $mimo)
    $farba = $null
    $all = [Vrstva]::Zloz($img, $bg, $wall, $obj, $a, $tien, (Get-Px 4), 0.07, 0.15, [ref]$farba)
    @{ img = $farba; alfa = $all; zone = $zone; obj = $a; tight = $tight; wgt = $wgt }
}

# Variant option "mierka": the object inside "roi" (with its shadow) scaled by "k" about "z",
# which moves to "do" (see Get-ScaleMask in spolocne.ps1; here the wall behind is the cladding).
function Set-LayerScale($layer, $v) {
    $s = $v.mierka
    $z = [double[]]$s.z
    $d = [double[]]$s.do
    $sel = Get-Rects ([double[]]$s.roi) $R
    $fs = $null
    $as = [Vrstva]::Mierka($layer.img, [Mapa]::Min($layer.alfa, $sel), $z[0] * $W, $z[1] * $H, $d[0] * $W, $d[1] * $H, [double]$s.k, [ref]$fs)
    $layer.img.Prekry($fs, [Mapa]::Prah($as, 0, 0.002))
    $layer.alfa = [Mapa]::Max([Mapa]::Min($layer.alfa, [Mapa]::Doplnok($sel)), $as)
}

# One cropped PNG per ROI rectangle grown by the shadow reach; every pixel goes to the first
# rectangle that contains it (overlapping pieces would darken twice).
function Save-Layer($layer, [string]$name, [double[]]$q) {
    $pieces = @()
    $taken = New-Object 'float[]' ($W * $H)
    for ($i = 0; $i -lt $q.Count; $i += 4) {
        $own = [Mapa]::Min((Get-Rects ([double[]]$q[$i..($i + 3)]) ($R + (Get-Px 2))), [Mapa]::Doplnok($taken))
        $taken = [Mapa]::Max($taken, $own)
        $a = [Mapa]::Min($layer.alfa, $own)
        $bb = [Mapa]::Ohranicenie($a, $W, $H, 0.004, 2)
        if ($bb[2] -eq 0) { continue }
        $file = "$name-$($i / 4).png"
        $layer.img.UlozPng((Join-Path $imgDir $file), $a, $bb[0], $bb[1], $bb[2], $bb[3])
        $pieces += [ordered]@{ src = "img/$file"; x = $bb[0]; y = $bb[1]; w = $bb[2]; h = $bb[3] }
    }
    if ($pieces.Count -eq 0) { Write-Warning "Layer $name is empty" }
    , $pieces
}

# --- Shelf accessories --------------------------------------------------------------------------
# Not a product: the original ones are pasted into every cladding image, their wall-like pixels
# (edges, shadows, the wall seen through the glass) moved pixel by pixel from the base without
# them to this cladding (as in zostav.ps1). Glass cannot be one layer for every cladding: what is
# seen through it would have to be both transparent and keep its colour.
$acc = Get-Accessories $results
$accNear = [Mapa]::Doplnok([Mapa]::Rozsir($acc.nove, $W, $H, (Get-Px 3)))   # product layers leave them out
$footprint = [Mapa]::Rozsir($acc.erase, $W, $H, (Get-Px 4))   # original objects with their shadows
function Add-Accessories($plate) {
    $low = $plate.Rozmaz((Get-Px 1))
    $obj = [Obr]::Prefarbi($acc.base, $acc.empty, $low, 25, 55)
    if ($acc.kluc) { $obj.Prekry([Obr]::Prefarbi($acc.base, $acc.empty, $low, 18, 32), [Mapa]::Zuz($acc.kluc, $W, $H, (Get-Px 1))) }
    $plate.Prekry($obj, $acc.nove)
}
$keys = @{}   # category id -> helper result with its original objects painted green
foreach ($k in @($n.kluce)) { if ($results.Contains($k.id)) { $keys[$k.kategoria] = $k.id } else { Write-Warning "No result for $($k.id)" } }

# --- Objects of the categories placed on every cladding ------------------------------------------
$layers = @{}   # category id -> option id -> pieces
foreach ($kat in @($cfg.kategorie | Where-Object { $_.naObkladoch })) {
    $q = [double[]]$kat.roi
    $mimo = [Mapa]::Min($accNear, $ones)
    if ($n.pred.($kat.id)) { $mimo = [Mapa]::Min($mimo, [Mapa]::Doplnok((Get-Rects ([double[]]$n.pred.($kat.id)) 0))) }
    $layers[$kat.id] = [ordered]@{}
    $srcs = @(@{ id = 'povodny'; img = $base; key = $(if ($kat.stary) { $kat.stary } else { $keys[$kat.id] }) })
    foreach ($v in @($cfg.varianty | Where-Object { $_.kategoria -eq $kat.id })) {
        if (-not $results.Contains($v.id)) { Write-Warning "No result for $($v.id), skipping"; continue }
        $key = $null
        if ($kat.promptKluc -or ($n.promptKluc.($kat.id) -and $results.Contains("$($v.id)#kluc"))) { $key = "$($v.id)#kluc" }
        $srcs += @{ id = $v.id; v = $v; img = (Get-Aligned $results $v.id $kat); key = $key }
    }
    foreach ($s in $srcs) {
        $img = $s.img
        $m = $mimo
        if ($s.key -and -not $kat.promptKluc) {
            # Fittings painted green (chrome in the shelf's shadow has almost the wall's tone; the
            # wall of a variant's generation drifts in tone, the bronze one pink under the shelf):
            # the key is drawn about as thick as the parts and is the object; a difference next to
            # it would add a light rim of the old wall.
            $key = (Get-Aligned $results $s.key $kat).Zelena(50, 110)
            [Mapa]::Oblast($key, $W, $H, $q)
            $o = [Mapa]::Min([Mapa]::Rozsir([Mapa]::Zuz($key, $W, $H, 1), $W, $H, 1), $m)
        } elseif ($s.key) {
            # Painted green by the model, a little too high (taller than the object) and not quite
            # exact at the edges: the top rows of the key come from the difference only; around the
            # key, where the object differs from the wall, it is added.
            $key = (Get-Aligned $results $s.key $kat).Zelena(50, 110)
            [Mapa]::Oblast($key, $W, $H, $q)
            $top = [Mapa]::Min($key, [Vrstva]::Posun($key, $W, $H, 0, (Get-Px 8)))
            $zone0 = [Mapa]::Max([Mapa]::Rozsir($key, $W, $H, $R), [Mapa]::Doplnok($m))
            if ($kat.stlpec) { $zone0 = [Mapa]::Max($zone0, (Get-Rects ([double[]]@($kat.stlpec[0], $q[1], $kat.stlpec[1], $q[3])) 0)) }
            $d = Get-Difference $img $zone0 $q 18 36
            $o = [Mapa]::Max([Mapa]::Min($d, [Mapa]::Rozsir($key, $W, $H, (Get-Px 2))), $top)
            $o = [Mapa]::Rozsir([Mapa]::Zuz($o, $W, $H, (Get-Px 1)), $W, $H, (Get-Px 1))
            # A tap behind the object: its column above the object's top edge is not this layer.
            if ($kat.stlpec) {
                $c = [double[]]$kat.stlpec
                $col = [float[]]$ones.Clone()
                $rim = [Mapa]::OrezStlpec($col, $o, $W, $H, $c[0], $c[1], 0.015, $kat.roi[1], 0.66, (Get-Px 4))
                if ($rim -lt 0) { Write-Warning "$($s.id): top edge not found, column not cleared" }
                else { Write-Host "    $($s.id): column cleared above y=$rim ($([Math]::Round($rim / $H, 3)))" }
                $m = [Mapa]::Min($m, $col)
            }
            $o = [Mapa]::Min($o, $m)
        } elseif ($s.v -and $kat.prazdny) {
            # Against the category's helper image without objects, generated from the same photo
            # like the variant: the empty scene has the tile joints and the glass edge a few pixels
            # off, which would come into the layer as thin lines of the old cladding.
            $o = [Mapa]::Min((Get-NewObject $results $s.v $kat $img), $m)
        } else {
            $o = [Mapa]::Min((Get-Difference $img (Get-Rects $q 0) $q 22 44), $m)
        }
        $outline = [Mapa]::Rozmaz([Mapa]::Rozsir($o, $W, $H, (Get-Px 1)), $W, $H, (Get-Px 1))
        # The key's outline is the object; without a key it is where it differs strongly.
        $tight = $null
        if ($s.key) { $tight = $o }
        $layer = New-Layer $img $outline $tight $q $m
        if ($s.id -eq 'povodny') { $footprint = [Mapa]::Max($footprint, $layer.zone) }
        if ($s.v.mierka) { Set-LayerScale $layer $s.v }
        $name = if ($s.id -eq 'povodny') { "$($kat.id)-povodny" } else { $s.id }
        $layers[$kat.id][$s.id] = Save-Layer $layer $name $q
        Save-Mask $layer.alfa "vrstva-$name"
        Save-Mask $layer.obj "objekt-$name"
        Save-Mask $layer.tight "isty-$name"
        Save-Mask $layer.wgt "stena-$name"
        Write-Host "  $name"
    }
}

# --- Claddings -------------------------------------------------------------------------------------
# The original one: the base photo with the empty scene (toned to it) where the original objects
# and their shadows were; each of them is a layer now.
$footprint = [Mapa]::Rozmaz($footprint, $W, $H, (Get-Px 2))
$plate = $base.Kopia()
$plate.Prekry((Get-Background $base $footprint), $footprint)
Add-Accessories $plate
$plate.UlozJpg((Join-Path $imgDir 'povodny.jpg'), 85)
Save-Mask $footprint 'podklad-povodny'
$plate = $null
$plateCat = $cfg.kategorie | Where-Object { $_.typ -eq 'podklad' } | Select-Object -First 1
$plateImg = @{}
foreach ($o in @($cfg.varianty | Where-Object { $_.kategoria -eq $plateCat.id })) {
    $id = "$($n.prazdna)@$($o.id)"
    if (-not $results.Contains($id)) { Write-Warning "No result for $id, skipping $($o.id)"; continue }
    $plate = Get-Aligned $results $id
    Add-Accessories $plate
    $plate.UlozJpg((Join-Path $imgDir "$($o.id).jpg"), 85)
    $plateImg[$o.id] = "img/$($o.id).jpg"
    Write-Host "  $($o.id)"
}
[GC]::Collect()

# --- Data: the previous approach from demo\index.html, with this approach's layers ----------------
$oldHtml = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'index.html'), [Text.Encoding]::UTF8)
$m = [regex]::Match($oldHtml, '(?s)/\*DATA\*/window\.KUPELNA = (.*?);/\*/DATA\*/')
if (-not $m.Success) { throw 'demo\index.html has no data (run zostav.ps1).' }
$prefix = '../demo/'
function Get-Prefixed($node) {
    # Every relative image path ("img/...") of the previous data, as seen from demo2\.
    $json = $node | ConvertTo-Json -Depth 12 -Compress
    $json = [regex]::Replace($json, '"(img/[^"]+)"', { param($x) '"' + $prefix + $x.Groups[1].Value + '"' })
    $json | ConvertFrom-Json
}
$old = Get-Prefixed ($m.Groups[1].Value | ConvertFrom-Json)
$new = $m.Groups[1].Value | ConvertFrom-Json
$new = Get-Prefixed $new
$new.povodny = 'img/povodny.jpg'
foreach ($kd in $new.kategorie) {
    foreach ($o in $kd.moznosti) {
        if ($kd.typ -eq 'podklad') {
            if ($o.id -ne 'povodny') { $o.obrazok = $plateImg[$o.id] }
        } elseif ($layers.ContainsKey($kd.id)) {
            $o | Add-Member -NotePropertyName vrstvy -NotePropertyValue ([ordered]@{ '*' = $layers[$kd.id][$o.id] }) -Force
        }
    }
    if ($kd.typ -eq 'podklad') { $kd.moznosti = @($kd.moznosti | Where-Object { $_.id -eq 'povodny' -or $_.obrazok }) }
}
$new.model = $cfg.model
$new.PSObject.Properties.Remove('kreditovZaObrazok')

$indexPath = Join-Path $outDir 'index.html'
$html = [IO.File]::ReadAllText($indexPath, [Text.Encoding]::UTF8)
$pattern = '(?s)(/\*DATA\*/).*?(/\*/DATA\*/)'
if ($html -notmatch $pattern) { throw 'demo2\index.html has no /*DATA*/ ... /*/DATA*/ block.' }
$data = "window.KUPELNA = $($new | ConvertTo-Json -Depth 12 -Compress);window.KUPELNA_A = $($old | ConvertTo-Json -Depth 12 -Compress);"
$html = [regex]::Replace($html, $pattern, { param($x) $x.Groups[1].Value + $data + $x.Groups[2].Value })
[IO.File]::WriteAllText($indexPath, $html, (New-Object Text.UTF8Encoding $false))
Write-Host 'demo2\index.html data updated.'

# --- Optional sample composites, drawn from the saved pieces exactly like the page ---------------
if ($Ladenie) {
    Add-Type -AssemblyName System.Drawing
    $combos = @(
        @('povodny'),
        @('obklad-graphit', 'dlazba-amani', 'baterie-black', 'umyvadlo-okruhle', 'zlab-grafit'),
        @('obklad-calacatta', 'dlazba-graphite', 'baterie-bronze', 'umyvadlo-savoy'),
        @('obklad-graphit', 'baterie-bronze', 'umyvadlo-savoy'),
        @('obklad-travertine', 'dlazba-graphite', 'baterie-black', 'umyvadlo-okruhle'),
        @('obklad-graphit')
    )
    $c = 0
    foreach ($combo in $combos) {
        $c++
        $plateId = @($combo | Where-Object { $_ -like "$($plateCat.id)-*" })[0]
        $file = if ($plateId) { Join-Path $imgDir "$plateId.jpg" } else { Join-Path $imgDir 'povodny.jpg' }
        if (-not (Test-Path -LiteralPath $file)) { continue }
        $src = [System.Drawing.Image]::FromFile($file)
        $bmp = New-Object System.Drawing.Bitmap $src
        $src.Dispose()
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $lists = @()
        foreach ($kd in @($new.kategorie | Where-Object { $_.typ -ne 'podklad' } | Sort-Object { $_.z })) {
            $chosen = @($kd.moznosti | Where-Object { $combo -contains $_.id })[0]
            if (-not $chosen) { $chosen = $kd.moznosti[0] }
            if ($chosen.vrstvy -and $chosen.vrstvy.'*') { $lists += , @($chosen.vrstvy.'*') }
        }
        foreach ($list in $lists) {
            foreach ($p in $list) {
                $path = Join-Path $outDir ($p.src -replace '/', '\')
                $pi = [System.Drawing.Image]::FromFile([IO.Path]::GetFullPath($path))
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

$files = Get-ChildItem $imgDir
Write-Host "Done: $($files.Count) files, $([Math]::Round((($files | Measure-Object Length -Sum).Sum) / 1MB, 1)) MB in $imgDir"
