<#
.SYNOPSIS
  Generates the variants from varianty.json via ..\kie-image.ps1 (in parallel)
  and records the resulting images in vysledky.json.

  Variants of a category with "naObkladoch": true are also generated on top of every
  wall-cladding result (task id "<variant>@<obklad variant>"), so the object sits on the
  right tiles and its layer has no halo from the original wall.

.EXAMPLE
  & .\demo\generuj.ps1                                   # everything that has no result yet
  & .\demo\generuj.ps1 -Ids baterie-bronze@obklad-graphit  # one task
  & .\demo\generuj.ps1 -Ids baterie-black                # a variant and all its per-tile tasks
  & .\demo\generuj.ps1 -Ids baterie-black -Force         # regenerate even if results exist
#>
param(
    [string[]]$Ids,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$kie = Join-Path $root 'kie-image.ps1'
$resultsPath = Join-Path $PSScriptRoot 'vysledky.json'

$cfg = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'varianty.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$results = [ordered]@{}
if (Test-Path -LiteralPath $resultsPath) {
    $old = Get-Content -LiteralPath $resultsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($p in $old.PSObject.Properties) { $results[$p.Name] = $p.Value }
}

$plateCat = $cfg.kategorie | Where-Object { $_.typ -eq 'podklad' } | Select-Object -First 1
$plates = @($cfg.varianty | Where-Object { $_.kategoria -eq $plateCat.id })

$tasks = foreach ($v in $cfg.varianty) {
    [pscustomobject]@{ id = $v.id; v = $v; podklad = Join-Path $root $cfg.podklad }
    $kat = $cfg.kategorie | Where-Object { $_.id -eq $v.kategoria }
    if (-not $kat.naObkladoch) { continue }
    foreach ($o in $plates) {
        $id = "$($v.id)@$($o.id)"
        if (-not $results.Contains($o.id)) {
            Write-Warning "$id skipped: $($o.id) has no result yet (generate it first)."
            continue
        }
        [pscustomobject]@{ id = $id; v = $v; podklad = Join-Path $root $results[$o.id].subor }
    }
}

$todo = @($tasks | Where-Object {
    (-not $Ids -or $Ids -contains $_.id -or $Ids -contains $_.v.id) -and ($Force -or -not $results.Contains($_.id))
})
if ($todo.Count -eq 0) { Write-Host 'Nothing to generate.'; return }

$jobs = foreach ($t in $todo) {
    $images = @($t.podklad) + @($t.v.referencie | ForEach-Object { Join-Path $root $_ })
    Write-Host "Starting $($t.id) ($($images.Count - 1) reference image(s))"
    Start-Job -Name $t.id -ArgumentList $kie, $t.v.prompt, $images, $cfg.aspectRatio, $cfg.resolution -ScriptBlock {
        param($kie, $prompt, $images, $ratio, $res)
        Set-ExecutionPolicy -Scope Process Bypass -Force
        & $kie -Prompt $prompt -Images $images -AspectRatio $ratio -Resolution $res
    }
}

$jobs | Wait-Job | Out-Null
foreach ($job in $jobs) {
    try {
        $out = @(Receive-Job $job -ErrorAction Stop | Where-Object { $_ -is [string] -and (Test-Path -LiteralPath $_) })
        if ($out.Count -eq 0) { throw 'no image downloaded' }
        $file = $out[0]
        $meta = Get-Content -LiteralPath ($file -replace '_\d+\.\w+$', '.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $results[$job.Name] = [ordered]@{
            subor  = $file.Substring($root.Length + 1)
            taskId = $meta.taskId
            sekund = $meta.durationSec
        }
        Write-Host "OK   $($job.Name): $file"
    } catch {
        Write-Warning "FAIL $($job.Name): $($_.Exception.Message)"
    }
    Remove-Job $job
}

[IO.File]::WriteAllText($resultsPath, ($results | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false))
