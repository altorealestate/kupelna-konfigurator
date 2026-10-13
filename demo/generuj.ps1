<#
.SYNOPSIS
  Generates the variants from varianty.json via ..\kie-image.ps1 (in parallel)
  and records the resulting images in vysledky.json.

.EXAMPLE
  & .\demo\generuj.ps1                         # all variants that have no result yet
  & .\demo\generuj.ps1 -Ids baterie-black      # only selected variants
  & .\demo\generuj.ps1 -Ids baterie-black -Force   # regenerate even if a result exists
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

$todo = @($cfg.varianty | Where-Object {
    (-not $Ids -or $Ids -contains $_.id) -and ($Force -or -not $results.Contains($_.id))
})
if ($todo.Count -eq 0) { Write-Host 'Nothing to generate.'; return }

$jobs = foreach ($v in $todo) {
    $images = @(Join-Path $root $cfg.podklad) + @($v.referencie | ForEach-Object { Join-Path $root $_ })
    Write-Host "Starting $($v.id) ($($images.Count - 1) reference image(s))"
    Start-Job -Name $v.id -ArgumentList $kie, $v.prompt, $images, $cfg.aspectRatio, $cfg.resolution -ScriptBlock {
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
