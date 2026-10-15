<#
.SYNOPSIS
  Generates the variants from varianty.json via ..\openai-image.ps1 (or ..\kie-image.ps1 with
  "generator": "kie"; in parallel, in stages ordered by dependency) and records the results in
  vysledky.json, each with its alignment to the base frame (at 4K the model re-frames the
  scene slightly).

  - helper images ("pomocne") and plain variants are generated from the base photo,
  - a variant or helper with "zVariantu" is generated from another variant's or helper's result
    (bronze taps are recoloured black ones, so both have the same shape, size and position),
  - the shelf accessories ("doplnky"), which every cladding generation redraws, are removed
    from each cladding ("prazdne-doplnky@<obklad>"); zostav.ps1 pastes the original ones back,
  - the reflection in the mirror ("zrkadlo") is repainted with each cladding ("zrkadlo@<obklad>",
    from the cladding without accessories),
  - for categories with "naObkladoch" the object of each variant is cut out (difference
    against the category's helper image without objects, "prazdny", or a copy in which the
    model painted the object pure green, "<variant>#kluc"), pasted onto every wall-cladding
    result, and the model only cleans up around it ("<variant>@<obklad>"). The object
    therefore keeps its size and position on every cladding.

.EXAMPLE
  & .\demo\generuj.ps1                                    # everything that has no result yet
  & .\demo\generuj.ps1 -Ids baterie-black@obklad-graphit  # one task
  & .\demo\generuj.ps1 -Ids baterie-black*                # a variant and all its per-tile tasks (wildcards)
  & .\demo\generuj.ps1 -Ids baterie-black* -Force         # regenerate even if results exist
  & .\demo\generuj.ps1 -Ids obklad-x,*@obklad-x -Plan     # only list the tasks, their order and cost (free)
#>
param(
    [string[]]$Ids,
    [switch]$Force,
    [switch]$Plan
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'spolocne.ps1')
# Image generator ("generator" in varianty.json): OpenAI Images API, or kie.ai (older results).
$generator = 'openai'
if ($cfg.generator) { $generator = [string]$cfg.generator }
$genScript = Join-Path $root (@{ openai = 'openai-image.ps1'; kie = 'kie-image.ps1' }[$generator])
$genArgs = @{ AspectRatio = $cfg.aspectRatio; Resolution = $cfg.resolution; TimeoutSec = 900 }
if ($generator -eq 'openai') {
    # Synchronous API: a request cut off on our side is billed anyway.
    $genArgs.TimeoutSec = 1800
    if ($cfg.model) { $genArgs.Model = $cfg.model }
    if ($cfg.kvalita) { $genArgs.Quality = $cfg.kvalita }
}
$inputDir = 'vystupy\vstupy'
New-Item -ItemType Directory -Force -Path (Join-Path $root $inputDir) | Out-Null
$results = Read-Results

$plateCat = $cfg.kategorie | Where-Object { $_.typ -eq 'podklad' } | Select-Object -First 1
$plates = @($cfg.varianty | Where-Object { $_.kategoria -eq $plateCat.id })
$plateIds = @($plates | ForEach-Object { $_.id })

# The claddings and everything generated on them ("<...>@<cladding>") use the cladding category's
# "resolution" when it has one (2K: at 4K the model drew the stone as a grainy relief); the result
# is stretched to the base frame when it is aligned.
function Get-Resolution([string]$id) {
    if ($plateCat.resolution -and $plateIds -contains ($id -replace '^.*@', '')) { return [string]$plateCat.resolution }
    [string]$cfg.resolution
}

$tasks = @(foreach ($p in @($cfg.pomocne)) {
    $refs = @($p.referencie | Where-Object { $_ } | ForEach-Object { Join-Path $root $_ })
    if ($p.zVariantu) {
        $kat = $cfg.kategorie | Where-Object { $_.id -eq $p.kategoria }
        [pscustomobject]@{ id = $p.id; prompt = $p.prompt; refs = $refs; deps = @($p.zVariantu); typ = 'zVariantu'; zdroj = $p.zVariantu; kat = $kat }
    } else {
        [pscustomobject]@{ id = $p.id; prompt = $p.prompt; refs = $refs; deps = @(); typ = 'podklad' }
    }
})
if ($cfg.doplnky) {
    $empty = $cfg.pomocne | Where-Object { $_.id -eq $cfg.doplnky.prazdny }
    foreach ($o in $plates) {
        $tasks += [pscustomobject]@{ id = "$($empty.id)@$($o.id)"; prompt = $empty.prompt; refs = @(); deps = @($o.id); typ = 'zVariantu'; zdroj = $o.id; kat = $null }
    }
}
if ($cfg.zrkadlo) {
    # The reflection in the mirror shows the opposite wall, which the cladding generations leave
    # in the original cladding. It is repainted on the cladding without the shelf accessories.
    foreach ($o in $plates) {
        $src = $o.id
        if ($cfg.doplnky) { $src = "$($cfg.doplnky.prazdny)@$($o.id)" }
        $refs = @($o.referencie | ForEach-Object { Join-Path $root $_ })
        $tasks += [pscustomobject]@{ id = "$($cfg.zrkadlo.id)@$($o.id)"; prompt = $cfg.zrkadlo.prompt; refs = $refs; deps = @($src); typ = 'zVariantu'; zdroj = $src; kat = $null }
    }
}
foreach ($v in $cfg.varianty) {
    $kat = $cfg.kategorie | Where-Object { $_.id -eq $v.kategoria }
    $refs = @($v.referencie | ForEach-Object { Join-Path $root $_ })
    if ($v.zVariantu) {
        $tasks += [pscustomobject]@{ id = $v.id; prompt = $v.prompt; refs = $refs; deps = @($v.zVariantu); typ = 'zVariantu'; zdroj = $v.zVariantu; kat = $kat }
    } else {
        $tasks += [pscustomobject]@{ id = $v.id; prompt = $v.prompt; refs = $refs; deps = @(); typ = 'podklad' }
    }
    if (-not $kat.naObkladoch) { continue }
    if ($kat.promptKluc) {
        $tasks += [pscustomobject]@{
            id = "$($v.id)#kluc"; prompt = $kat.promptKluc.Replace('{popis}', $v.popis); refs = @()
            deps = @($v.id); typ = 'zVariantu'; zdroj = $v.id; kat = $kat
        }
    }
    foreach ($o in $plates) {
        $tasks += [pscustomobject]@{
            id = "$($v.id)@$($o.id)"; prompt = $kat.promptNaObklad.Replace('{popis}', $v.popis); refs = @()
            deps = @($v.id, $o.id) + @(Get-ObjectDeps $v $kat); typ = 'naObklad'; v = $v; o = $o; kat = $kat
        }
    }
}

$waiting = New-Object System.Collections.ArrayList
foreach ($t in $tasks) {
    $id = $t.id
    $match = -not $Ids -or @($Ids | Where-Object { $id -like $_ }).Count -gt 0
    if ($match -and ($Force -or -not $results.Contains($t.id))) { [void]$waiting.Add($t) }
}
if ($waiting.Count -eq 0) { Write-Host 'Nothing to generate.'; return }

# Dry run: the stages the loop below would run and their cost.
if ($Plan) {
    $done = @($results.Keys)
    $left = @($waiting)
    $stage = 0
    while ($left.Count -gt 0) {
        $pending = @($left | ForEach-Object { $_.id })
        $ready = @($left | Where-Object {
            @($_.deps | Where-Object { $done -notcontains $_ -or $pending -contains $_ }).Count -eq 0
        })
        if ($ready.Count -eq 0) { Write-Warning "Cannot generate, inputs are missing: $($pending -join ', ')"; break }
        $stage++
        Write-Host "Stage ${stage}:"
        foreach ($t in $ready) {
            $from = 'base photo'
            if ($t.deps) { $from = $t.deps -join ', ' }
            Write-Host "  $($t.id)  <- $from"
        }
        $done += @($ready | ForEach-Object { $_.id })
        $left = @($left | Where-Object { $ready -notcontains $_ })
    }
    if ($generator -eq 'kie') {
        foreach ($g in @($waiting | Group-Object { Get-Resolution $_.id })) {
            $per = $creditsPerImage[$g.Name]
            Write-Host ("{0} generation(s) x {1} kie.ai credits ({2}) = {3} credits, about `${4:N2}" -f $g.Count, $per, $g.Name, ($g.Count * $per), ($g.Count * $per * 0.005))
        }
        try { Write-Host "kie.ai balance: $(& $genScript -Credits) credits" } catch { Write-Warning "Balance not available: $($_.Exception.Message)" }
        return
    }
    # OpenAI bills tokens: the estimate is the average of earlier results with the same settings.
    $model = $genArgs.Model; $quality = $genArgs.Quality
    if (-not $model) { $model = 'gpt-image-2.5-sunburst' }
    if (-not $quality) { $quality = 'high' }
    $earlier = @(Get-ChildItem -LiteralPath (Join-Path $root 'vystupy') -Filter '*.json' -File | ForEach-Object {
        try { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    } | Where-Object { $_.api -eq 'openai' -and $_.costUsd -and $_.model -eq $model -and $_.param.quality -eq $quality })
    foreach ($g in @($waiting | Group-Object { Get-Resolution $_.id })) {
        $n = $g.Count
        $costs = @($earlier | Where-Object { $_.param.resolution -eq $g.Name } | ForEach-Object { [double]$_.costUsd })
        if ($costs.Count) {
            $avg = ($costs | Measure-Object -Average).Average
            Write-Host ("{0} generation(s) in {1} x about `${2:N3} ({3}, quality {4}; average of {5} earlier) = about `${6:N2}" -f $n, $g.Name, $avg, $model, $quality, $costs.Count, ($n * $avg))
        } else {
            Write-Host "$n generation(s) in $($g.Name) with $model, quality $quality. OpenAI bills tokens; the price is known after the first result (costUsd in its .json)."
        }
    }
    return
}

# Prepares the input image of a task (in the base frame); returns its path relative to $root.
function New-TaskInput($t) {
    switch ($t.typ) {
        'podklad' { return $cfg.podklad }
        'zVariantu' { $img = Get-Aligned $results $t.zdroj $t.kat }
        'naObklad' {
            $img = Get-Aligned $results $t.o.id
            $obj = Get-Aligned $results $t.v.id $t.kat
            if ($t.v.mierka) { Set-Scale $results $obj $t.v $t.kat (Get-ScaleMask $results $t.v $t.kat) }
            $mask = Get-NewObject $results $t.v $t.kat $obj
            # The object's edge pixels carry the original background (a light halo on dark tiles,
            # which the model then keeps around bronze); they are moved to this cladding's
            # background. With a helper image without objects the background is known per pixel,
            # otherwise it is estimated from the surroundings.
            if ($t.kat.prazdny) {
                # Roughly erase the original objects with the surrounding wall colour, so the
                # model repaints the tiles there instead of keeping faint ghosts of them.
                $old = Get-OldObjects $results $t.kat
                $img.Prekry($img.RozmazVazene([Mapa]::Doplnok($old), (Get-Px 20)), $old)
                $bgBase = (Get-Aligned $results $t.kat.prazdny $t.kat).Rozmaz((Get-Px 1))
                $bgPlate = $img.Rozmaz((Get-Px 1))
            } else {
                $base = Get-Input $cfg.podklad
                $old = Get-Mask $obj $t.kat $base.Rozmaz((Get-Px 2))
                # Erase the whole old object (thin leftovers next to a new washbasin are kept by
                # the model as part of the design): the wall is filled smoothly from around it,
                # the shelf ("polica") is the same on every cladding and comes from the variant.
                $hole = Get-OldObjects $results $t.kat
                $img.Prekry([Obr]::Vyrovnanie($img, (New-Object Obr $W, $H), $hole, (Get-Px 6), 3000, 1000), $hole)
                if ($t.kat.polica) { $img.Prekry($obj, [Mapa]::Min($hole, [Mapa]::Riadky($W, $H, [double]$t.kat.polica, (Get-Px 2)))) }
                $keep = [Mapa]::Doplnok([Mapa]::Rozsir([Mapa]::Max($old, $mask), $W, $H, (Get-Px 6)))
                $bgBase = $base.RozmazVazene($keep, (Get-Px 10))
                $bgPlate = $img.RozmazVazene($keep, (Get-Px 10))
            }
            $obj = [Obr]::Prefarbi($obj, $bgBase, $bgPlate, 25, 55)
            $img.Prekry($obj, $mask)
        }
    }
    $rel = Join-Path $inputDir "$($t.id).jpg"
    $img.UlozJpg((Join-Path $root $rel), 95)
    $rel
}

while ($waiting.Count -gt 0) {
    $pending = @($waiting | ForEach-Object { $_.id })
    $ready = @($waiting | Where-Object {
        @($_.deps | Where-Object { -not $results.Contains($_) -or $pending -contains $_ }).Count -eq 0
    })
    if ($ready.Count -eq 0) {
        Write-Warning "Cannot generate, inputs are missing: $($pending -join ', ')"
        break
    }

    $jobs = foreach ($t in $ready) {
        $in = New-TaskInput $t
        $images = @((Join-Path $root $in)) + $t.refs
        $opts = $genArgs.Clone()
        $opts.Resolution = Get-Resolution $t.id
        Write-Host "Starting $($t.id) ($($images.Count - 1) reference image(s), $($opts.Resolution))"
        $job = Start-Job -Name $t.id -ArgumentList $genScript, $t.prompt, $images, $opts -ScriptBlock {
            param($script, $prompt, $images, $opts)
            Set-ExecutionPolicy -Scope Process Bypass -Force
            & $script -Prompt $prompt -Images $images @opts
        }
        $job | Add-Member -NotePropertyMembers @{ Vstup = $in; Zmensene = ($t.typ -eq 'naObklad' -and [bool]$t.v.mierka) } -PassThru
    }

    $jobs | Wait-Job | Out-Null
    foreach ($job in $jobs) {
        try {
            $out = @(Receive-Job $job -ErrorAction Stop | Where-Object { $_ -is [string] -and (Test-Path -LiteralPath $_) })
            if ($out.Count -eq 0) { throw 'no image downloaded' }
            $file = $out[0]
            $meta = Get-Content -LiteralPath ($file -replace '_\d+\.\w+$', '.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            $al = [Zarovnanie]::Najdi((Get-Input $job.Vstup), $file)
            $results[$job.Name] = [ordered]@{
                subor      = $file.Substring($root.Length + 1)
                taskId     = $meta.taskId
                sekund     = $meta.durationSec
                vstup      = $job.Vstup
                zarovnanie = @([Math]::Round($al[0], 5), [Math]::Round($al[1], 5), [Math]::Round($al[2], 2), [Math]::Round($al[3], 2))
                zhoda      = [Math]::Round($al[4], 3)
            }
            $price = ''
            if ($meta.costUsd) { $results[$job.Name].cenaUsd = $meta.costUsd; $price = (", `${0:N3}" -f $meta.costUsd) }
            # The input already had the object scaled ("mierka"), zostav must not scale it again.
            if ($job.Zmensene) { $results[$job.Name].zmensene = $true }
            Write-Host ("OK   {0}: {1}  (scale {2:N4} x {3:N4}, shift {4:N1}, {5:N1} px, match {6:N2}{7})" -f $job.Name, $file, $al[0], $al[1], $al[2], $al[3], $al[4], $price)
        } catch {
            Write-Warning "FAIL $($job.Name): $($_.Exception.Message)"
        }
        Remove-Job $job
    }
    Save-Results $results
    foreach ($t in $ready) { $waiting.Remove($t) }
}
