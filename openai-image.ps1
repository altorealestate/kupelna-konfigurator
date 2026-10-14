<#
.SYNOPSIS
  Image editing via the OpenAI Images API (default model: gpt-image-2.5-sunburst).

.DESCRIPTION
  Sends the images (first = the photo to edit, rest = product references) with the prompt to
  POST /v1/images/edits and saves the result into -OutDir together with a .json sidecar
  (request id, duration, token usage and its price). Writes the path of the saved image to
  the pipeline, like kie-image.ps1.

  The API answers synchronously: there is no task to resume, and a request that times out on
  our side is billed anyway, so the timeout is generous. OpenAI bills tokens, not images;
  costUsd in the sidecar is computed from the usage the API returns.

  API key: $env:OPENAI_API_KEY, the User environment variable OPENAI_API_KEY, or
  OPENAI_API_KEY=... in .env next to this script.

.EXAMPLE
  & .\openai-image.ps1 -Prompt "Replace the wall tiles with ..." -Images '.\foto.jpg', '.\obklad.jpg' -Resolution 1K

.EXAMPLE
  & .\openai-image.ps1 -Prompt "..." -Images '.\foto.jpg' -Size 3312x2480 -Quality xhigh

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\openai-image.ps1 -Prompt "..." -Images ".\foto.jpg|.\obklad.jpg"
  (with -File, separate multiple images with '|')
#>
param(
    [string]$Prompt,
    [string]$PromptFile,

    # Local paths or http(s) URLs. First = the photo to edit, rest = references (at most 16).
    [string[]]$Images = @(),

    # WIDTHxHEIGHT (multiples of 16, at most 3840 per side and 8 294 400 pixels) or auto.
    # Without it, -Resolution chooses the size with the aspect of -AspectRatio or of the first image.
    [string]$Size,

    [ValidateSet('1K', '2K', '4K')]
    [string]$Resolution = '1K',

    [string]$AspectRatio = 'auto',

    [ValidateSet('low', 'medium', 'high', 'xhigh', 'max', 'auto')]
    [string]$Quality = 'high',

    [ValidateSet('auto', 'opaque', 'transparent')]
    [string]$Background = 'auto',

    [string]$Model = 'gpt-image-2.5-sunburst',

    [string]$OutDir,

    [int]$TimeoutSec = 1800
)

$ErrorActionPreference = 'Stop'

$ApiBase = 'https://api.openai.com/v1'
$MaxImageBytes = 50MB
$MaxImages = 16
$MimeTypes = @{ '.jpg' = 'image/jpeg'; '.jpeg' = 'image/jpeg'; '.png' = 'image/png'; '.webp' = 'image/webp' }
# Pixel budget per resolution. 4K = 3312x2480 for 4:3, the frame kie.ai returned (API limit 8 294 400).
$PixelBudget = @{ '1K' = 1048576; '2K' = 3145728; '4K' = 8213760 }
# USD per 1M tokens: text input, image input, image output (Standard; the gpt-image-2 family).
$Rates = @{ 'gpt-image-2*' = @(5.0, 8.0, 30.0) }

if (-not $OutDir) { $OutDir = Join-Path $PSScriptRoot 'vystupy' }

# --- API key -------------------------------------------------------------------
$ApiKey = $env:OPENAI_API_KEY
if (-not $ApiKey) { $ApiKey = [Environment]::GetEnvironmentVariable('OPENAI_API_KEY', 'User') }
$envFile = Join-Path $PSScriptRoot '.env'
if (-not $ApiKey -and (Test-Path -LiteralPath $envFile)) {
    $line = Get-Content -LiteralPath $envFile | Where-Object { $_ -match '^\s*OPENAI_API_KEY\s*=' } | Select-Object -First 1
    if ($line) { $ApiKey = ($line -replace '^\s*OPENAI_API_KEY\s*=\s*', '').Trim().Trim('"', "'") }
}
if (-not $ApiKey) {
    throw "OPENAI_API_KEY is not set. Set it with: [Environment]::SetEnvironmentVariable('OPENAI_API_KEY', '<key>', 'User')"
}

# --- Inputs --------------------------------------------------------------------
if ($PromptFile) { $Prompt = Get-Content -LiteralPath $PromptFile -Raw -Encoding UTF8 }
if (-not $Prompt -or -not $Prompt.Trim()) { throw 'Provide -Prompt or -PromptFile.' }
if ($Prompt.Length -gt 32000) { throw "Prompt is $($Prompt.Length) characters; the limit is 32000." }

# With -File, arrays arrive as one string; '|' cannot appear in Windows paths.
$imageList = @($Images | ForEach-Object { $_ -split '\|' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($imageList.Count -eq 0) { throw 'Provide at least one image with -Images.' }
if ($imageList.Count -gt $MaxImages) { throw "$($imageList.Count) images; the limit is $MaxImages." }

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Net.Http, System.Drawing, System.Web.Extensions

# URLs are downloaded: the edit endpoint takes uploaded files.
$tempFiles = @()
$files = @(foreach ($img in $imageList) {
    if ($img -match '^https?://') {
        $ext = [IO.Path]::GetExtension(([uri]$img).AbsolutePath).ToLowerInvariant()
        if (-not $MimeTypes.ContainsKey($ext)) { $ext = '.png' }
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N') + $ext)
        (New-Object System.Net.WebClient).DownloadFile($img, $tmp)
        $tempFiles += $tmp
        $tmp
    } else {
        if (-not (Test-Path -LiteralPath $img -PathType Leaf)) { throw "Image not found: $img" }
        (Get-Item -LiteralPath $img).FullName
    }
})
foreach ($f in $files) {
    $item = Get-Item -LiteralPath $f
    if (-not $MimeTypes.ContainsKey($item.Extension.ToLowerInvariant())) {
        throw "Unsupported image type '$($item.Extension)' ($f); use jpg, jpeg, png or webp."
    }
    if ($item.Length -gt $MaxImageBytes) { throw "Image is $([Math]::Round($item.Length / 1MB, 1)) MB, the limit is 50 MB: $f" }
}

# Size: WIDTHxHEIGHT in multiples of 16 with the requested aspect, within the API limits.
$sizeFrom = $null
if (-not $Size) {
    if ($AspectRatio -match '^(\d+):(\d+)$') {
        $aspect = [double]$Matches[1] / [double]$Matches[2]
    } else {
        $first = [System.Drawing.Image]::FromFile($files[0])
        $aspect = $first.Width / [double]$first.Height
        $first.Dispose()
    }
    $sizeFrom = $Resolution
    $px = $PixelBudget[$Resolution]
    $w = [int]([Math]::Round([Math]::Sqrt($px * $aspect) / 16) * 16)
    $h = [int]([Math]::Round($w / $aspect / 16) * 16)
    while ($w -gt 3840 -or $h -gt 3840 -or $w * $h -gt 8294400) {
        $w -= 16
        $h = [int]([Math]::Round($w / $aspect / 16) * 16)
    }
    $Size = "${w}x$h"
}
if ($Size -ne 'auto' -and $Size -notmatch '^\d+x\d+$') { throw "Size must be WIDTHxHEIGHT or auto, not '$Size'." }

# --- Request -------------------------------------------------------------------
# Adds a multipart part with curl-style headers (quoted name, no filename*).
function Add-FormPart($Form, $Part, [string]$Name, [string]$FileName) {
    $cd = New-Object System.Net.Http.Headers.ContentDispositionHeaderValue('form-data')
    $cd.Name = "`"$Name`""
    if ($FileName) { $cd.FileName = "`"$FileName`"" }
    $Part.Headers.ContentDisposition = $cd
    $Form.Add($Part)
}

$form = New-Object System.Net.Http.MultipartFormDataContent
$fields = [ordered]@{ model = $Model; prompt = $Prompt; size = $Size; quality = $Quality; background = $Background; output_format = 'png'; n = '1' }
foreach ($k in $fields.Keys) {
    $text = New-Object System.Net.Http.StringContent([string]$fields[$k], [Text.Encoding]::UTF8)
    $text.Headers.ContentType = $null
    Add-FormPart $form $text $k
}
$streams = @()
try {
    for ($i = 0; $i -lt $files.Count; $i++) {
        $ext = [IO.Path]::GetExtension($files[$i]).ToLowerInvariant()
        $stream = [IO.File]::OpenRead($files[$i])
        $streams += $stream
        $part = New-Object System.Net.Http.StreamContent($stream)
        $part.Headers.ContentType = New-Object System.Net.Http.Headers.MediaTypeHeaderValue($MimeTypes[$ext])
        # ASCII names avoid trouble with diacritics/commas in catalog file names.
        Add-FormPart $form $part 'image[]' "image$i$ext"
    }

    $http = New-Object System.Net.Http.HttpClient
    $http.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)
    $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post, "$ApiBase/images/edits")
    $req.Headers.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $ApiKey)
    $req.Content = $form
    Write-Host "Sending $($files.Count) image(s) to $Model ($Size, quality $Quality) ..."
    $started = Get-Date
    try {
        $res = $http.SendAsync($req).GetAwaiter().GetResult()
    } catch {
        # PowerShell wraps the exception of a .NET call.
        if ($_.Exception.GetBaseException() -is [System.Threading.Tasks.TaskCanceledException]) {
            throw "No answer within $TimeoutSec s. The request may still be billed; it cannot be resumed."
        }
        # The outer message ("Error while copying content to a stream") does not say what failed.
        $chain = @(); $e = $_.Exception
        while ($e) { $chain += $e.Message; $e = $e.InnerException }
        throw "Request failed after $([Math]::Round(((Get-Date) - $started).TotalSeconds, 1)) s: $($chain -join ' <- ')"
    }
    $text = $res.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    $durationSec = [Math]::Round(((Get-Date) - $started).TotalSeconds, 1)
} finally {
    foreach ($s in $streams) { $s.Dispose() }
    foreach ($t in $tempFiles) { Remove-Item -LiteralPath $t -ErrorAction SilentlyContinue }
}

# The answer carries the image as base64 (tens of MB at 4K): ConvertFrom-Json would hit its limit.
$json = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$json.MaxJsonLength = [int]::MaxValue
$body = $null
try { $body = $json.DeserializeObject($text) } catch { }
$requestId = $null
$values = $null
if ($res.Headers.TryGetValues('x-request-id', [ref]$values)) { $requestId = @($values)[0] }
if (-not $res.IsSuccessStatusCode) {
    $msg = $text
    if ($body -and $body['error']) { $msg = "$($body['error']['code']) $($body['error']['message'])" }
    throw "OpenAI images/edits failed: HTTP $([int]$res.StatusCode): $msg (request $requestId)"
}
$data = @($body['data'])
if ($data.Count -eq 0 -or -not $data[0]['b64_json']) { throw "OpenAI returned no image (request $requestId)." }

# --- Save ----------------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$id = if ($requestId) { $requestId -replace '^req_', '' } else { [guid]::NewGuid().ToString('N') }
$prefix = "$(Get-Date -Format 'yyyyMMdd-HHmmss')_$($id.Substring(0, [Math]::Min(8, $id.Length)))"
$format = if ($body['output_format']) { $body['output_format'] } else { 'png' }
$saved = @()
for ($i = 0; $i -lt $data.Count; $i++) {
    $path = Join-Path $OutDir "$prefix`_$($i + 1).$format"
    [IO.File]::WriteAllBytes($path, [Convert]::FromBase64String($data[$i]['b64_json']))
    $saved += $path
}

$usage = $body['usage']
$costUsd = $null
$rate = $Rates.GetEnumerator() | Where-Object { $Model -like $_.Key } | Select-Object -First 1
if ($usage -and $rate) {
    $inDetails = $usage['input_tokens_details']
    $textIn = [double]$usage['input_tokens']
    $imageIn = 0.0
    if ($inDetails) { $textIn = [double]$inDetails['text_tokens']; $imageIn = [double]$inDetails['image_tokens'] }
    $r = $rate.Value
    $costUsd = [Math]::Round(($textIn * $r[0] + $imageIn * $r[1] + [double]$usage['output_tokens'] * $r[2]) / 1e6, 4)
}
$meta = [ordered]@{
    api         = 'openai'
    taskId      = $requestId
    model       = $Model
    state       = 'success'
    durationSec = $durationSec
    createTime  = $body['created']
    param       = [ordered]@{
        model = $Model; prompt = $Prompt; size = $Size; resolution = $sizeFrom; quality = $Quality; background = $Background
        images = @($imageList | ForEach-Object { if ($_ -match '^https?://') { $_ } else { Split-Path $_ -Leaf } })
    }
    size        = $body['size']
    usage       = $usage
    costUsd     = $costUsd
    files       = @($saved | ForEach-Object { Split-Path $_ -Leaf })
}
[IO.File]::WriteAllText((Join-Path $OutDir "$prefix.json"), ($meta | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding $false))

Write-Host "Done in $durationSec s$(if ($costUsd) { ", `$$costUsd" })."
$saved
