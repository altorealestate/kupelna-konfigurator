<#
.SYNOPSIS
  Image-to-image generation via kie.ai (default model: gpt-image-2-5-flare-image-to-image).

.DESCRIPTION
  Uploads local images to kie.ai file storage (the API only accepts public URLs),
  creates a generation task, polls until it finishes and downloads the results
  into -OutDir together with a .json sidecar describing the task.
  Writes the paths of the downloaded images to the pipeline.

  API key: $env:KIE_API_KEY, or the User environment variable KIE_API_KEY.

.EXAMPLE
  & .\kie-image.ps1 -Prompt "Replace the wall tiles with ..." -Images '.\foto.jpg', '.\obklad.jpg' -Resolution 2K

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\kie-image.ps1 -Prompt "..." -Images ".\foto.jpg|.\obklad.jpg"
  (with -File, separate multiple images with '|')

.EXAMPLE
  & .\kie-image.ps1 -TaskId 281e5b0...   # resume waiting for / downloading an existing task
#>
[CmdletBinding(DefaultParameterSetName = 'Create')]
param(
    [Parameter(ParameterSetName = 'Create')]
    [string]$Prompt,

    [Parameter(ParameterSetName = 'Create')]
    [string]$PromptFile,

    # Local paths or http(s) URLs. First = the photo to edit, rest = references.
    [Parameter(ParameterSetName = 'Create')]
    [string[]]$Images = @(),

    [Parameter(ParameterSetName = 'Create')]
    [ValidateSet('auto', '1:1', '3:2', '2:3', '16:9', '9:16', '4:3', '3:4', '21:9', '27:16', '16:27', '9:8', '8:9')]
    [string]$AspectRatio = 'auto',

    [Parameter(ParameterSetName = 'Create')]
    [ValidateSet('1K', '2K', '4K')]
    [string]$Resolution = '1K',

    [Parameter(ParameterSetName = 'Create')]
    [ValidateSet('auto', 'opaque', 'transparent')]
    [string]$Background = 'auto',

    [Parameter(ParameterSetName = 'Create')]
    [string]$Model = 'gpt-image-2-5-flare-image-to-image',

    [Parameter(ParameterSetName = 'Resume', Mandatory = $true)]
    [string]$TaskId,

    [string]$OutDir,

    [int]$TimeoutSec = 600,

    [int]$PollSec = 5
)

$ErrorActionPreference = 'Stop'

$ApiBase = 'https://api.kie.ai/api/v1'
$UploadEndpoint = 'https://kieai.redpandaai.co/api/file-stream-upload'
$UploadPath = 'vizualizacia-kupelna'
$MaxImageBytes = 30MB
$MimeTypes = @{ '.jpg' = 'image/jpeg'; '.jpeg' = 'image/jpeg'; '.png' = 'image/png'; '.webp' = 'image/webp' }
$OneKOnlyRatios = @('27:16', '16:27', '9:8', '8:9')
$ErrorHints = @{
    400 = 'invalid request parameters'
    401 = 'authentication failed - check KIE_API_KEY'
    402 = 'insufficient account balance'
    404 = 'resource not found'
    422 = 'parameter validation failed'
    429 = 'rate limit exceeded - try again later'
    500 = 'kie.ai internal server error'
}

if (-not $OutDir) { $OutDir = Join-Path $PSScriptRoot 'vystupy' }

# --- API key -------------------------------------------------------------------
$ApiKey = $env:KIE_API_KEY
if (-not $ApiKey) { $ApiKey = [Environment]::GetEnvironmentVariable('KIE_API_KEY', 'User') }
if (-not $ApiKey) {
    throw "KIE_API_KEY is not set. Set it with: [Environment]::SetEnvironmentVariable('KIE_API_KEY', '<key>', 'User')"
}

# --- HTTP ----------------------------------------------------------------------
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Net.Http
$Http = New-Object System.Net.Http.HttpClient
$Http.Timeout = [TimeSpan]::FromMinutes(5)

# Sends an authenticated request to kie.ai and returns the parsed JSON body.
# kie.ai reports some errors with HTTP 200 and a non-200 'code' field.
function Invoke-Kie([string]$Method, [string]$Url, [System.Net.Http.HttpContent]$Content) {
    $req = New-Object System.Net.Http.HttpRequestMessage((New-Object System.Net.Http.HttpMethod $Method), $Url)
    $req.Headers.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $ApiKey)
    if ($Content) { $req.Content = $Content }
    $res = $Http.SendAsync($req).GetAwaiter().GetResult()
    $text = $res.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    $json = $null
    try { $json = $text | ConvertFrom-Json } catch { }
    $code = [int]$res.StatusCode
    if ($json -and $json.code) { $code = [int]$json.code }
    if (-not $res.IsSuccessStatusCode -or $code -ne 200) {
        $msg = $text
        if ($json -and $json.msg) { $msg = $json.msg }
        $hint = ''
        if ($ErrorHints.ContainsKey($code)) { $hint = " ($($ErrorHints[$code]))" }
        throw "kie.ai $Method $Url failed: HTTP $([int]$res.StatusCode), code $code$hint`: $msg"
    }
    $json
}

# Adds a multipart part with curl-style headers. The upload server rejects the
# .NET defaults (unquoted name, extra filename*, text/plain on string fields).
function Add-FormPart($Form, $Part, [string]$Name, [string]$FileName) {
    $cd = New-Object System.Net.Http.Headers.ContentDispositionHeaderValue('form-data')
    $cd.Name = "`"$Name`""
    if ($FileName) { $cd.FileName = "`"$FileName`"" }
    $Part.Headers.ContentDisposition = $cd
    $Form.Add($Part)
}

function Send-KieFile([string]$Path) {
    $item = Get-Item -LiteralPath $Path
    $ext = $item.Extension.ToLowerInvariant()
    # ASCII name avoids trouble with diacritics/commas in catalog file names.
    $name = [guid]::NewGuid().ToString('N') + $ext
    $stream = [IO.File]::OpenRead($item.FullName)
    try {
        $boundary = '----kie' + [guid]::NewGuid().ToString('N')
        $form = New-Object System.Net.Http.MultipartFormDataContent($boundary)
        # .NET quotes the boundary in Content-Type; send it unquoted like curl.
        $form.Headers.Remove('Content-Type') | Out-Null
        $form.Headers.TryAddWithoutValidation('Content-Type', "multipart/form-data; boundary=$boundary") | Out-Null
        $file = New-Object System.Net.Http.StreamContent($stream)
        $file.Headers.ContentType = New-Object System.Net.Http.Headers.MediaTypeHeaderValue($MimeTypes[$ext])
        Add-FormPart $form $file 'file' $name
        foreach ($field in @(@('uploadPath', $UploadPath), @('fileName', $name))) {
            $text = New-Object System.Net.Http.StringContent($field[1])
            $text.Headers.ContentType = $null
            Add-FormPart $form $text $field[0]
        }
        $resp = Invoke-Kie 'POST' $UploadEndpoint $form
    } finally {
        $stream.Dispose()
    }
    if (-not $resp.data.downloadUrl) { throw "Upload of '$Path' returned no downloadUrl." }
    $resp.data.downloadUrl
}

# --- Create task ---------------------------------------------------------------
if ($PSCmdlet.ParameterSetName -eq 'Create') {
    if ($PromptFile) { $Prompt = Get-Content -LiteralPath $PromptFile -Raw -Encoding UTF8 }
    if (-not $Prompt -or -not $Prompt.Trim()) { throw 'Provide -Prompt or -PromptFile.' }
    if ($Prompt.Length -gt 20000) { throw "Prompt is $($Prompt.Length) characters; the limit is 20000." }
    if ($OneKOnlyRatios -contains $AspectRatio -and $Resolution -ne '1K') {
        throw "Aspect ratio $AspectRatio supports only 1K resolution."
    }

    # With -File, arrays arrive as one string; '|' cannot appear in Windows paths.
    $imageList = @($Images | ForEach-Object { $_ -split '\|' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

    foreach ($img in $imageList) {
        if ($img -match '^https?://') { continue }
        if (-not (Test-Path -LiteralPath $img -PathType Leaf)) { throw "Image not found: $img" }
        $item = Get-Item -LiteralPath $img
        if (-not $MimeTypes.ContainsKey($item.Extension.ToLowerInvariant())) {
            throw "Unsupported image type '$($item.Extension)' ($img); use jpg, jpeg, png or webp."
        }
        if ($item.Length -gt $MaxImageBytes) {
            throw "Image is $([Math]::Round($item.Length / 1MB, 1)) MB, the limit is 30 MB: $img"
        }
    }

    $inputUrls = @()
    foreach ($img in $imageList) {
        if ($img -match '^https?://') {
            $inputUrls += $img
        } else {
            Write-Host "Uploading $img ..."
            $inputUrls += Send-KieFile $img
        }
    }

    # Each model family names its inputs differently.
    if ($Model -like 'nano-banana*') {
        $taskInput = [ordered]@{
            prompt        = $Prompt
            aspect_ratio  = $AspectRatio
            resolution    = $Resolution
            output_format = 'png'
        }
        if ($inputUrls.Count -gt 0) { $taskInput.image_input = [string[]]$inputUrls }
    } elseif ($Model -like 'grok-imagine*') {
        # No resolution setting; only a few aspect ratios, otherwise keep the input's.
        $ratio = $AspectRatio
        if (@('1:1', '2:3', '3:2', '16:9', '9:16') -notcontains $ratio) { $ratio = 'auto' }
        $taskInput = [ordered]@{ prompt = $Prompt; aspect_ratio = $ratio }
        if ($inputUrls.Count -gt 0) { $taskInput.image_urls = [string[]]$inputUrls }
    } else {
        $taskInput = [ordered]@{
            prompt       = $Prompt
            aspect_ratio = $AspectRatio
            resolution   = $Resolution
            background   = $Background
        }
        if ($inputUrls.Count -gt 0) { $taskInput.input_urls = [string[]]$inputUrls }
    }
    $body = [ordered]@{ model = $Model; input = $taskInput } | ConvertTo-Json -Depth 10
    $content = New-Object System.Net.Http.StringContent($body, [Text.Encoding]::UTF8, 'application/json')

    $created = Invoke-Kie 'POST' "$ApiBase/jobs/createTask" $content
    $TaskId = $created.data.taskId
    if (-not $TaskId) { throw 'createTask returned no taskId.' }
    Write-Host "Task created: $TaskId"
}

# --- Poll ----------------------------------------------------------------------
$deadline = (Get-Date).AddSeconds($TimeoutSec)
$errors = 0
while ($true) {
    try {
        $record = (Invoke-Kie 'GET' "$ApiBase/jobs/recordInfo?taskId=$([uri]::EscapeDataString($TaskId))").data
        $errors = 0
    } catch {
        # Tolerate transient network/API hiccups while polling.
        $errors++
        if ($errors -ge 3) { throw }
        Write-Host "  poll error ($errors/3): $($_.Exception.Message)"
        Start-Sleep -Seconds $PollSec
        continue
    }
    $state = $record.state
    if ($state -eq 'success' -or $state -eq 'fail') { break }
    if ((Get-Date) -gt $deadline) {
        throw "Timed out after $TimeoutSec s; task is still '$state'. Resume with: -TaskId $TaskId"
    }
    Write-Host "  state: $state ..."
    Start-Sleep -Seconds $PollSec
}

if ($state -eq 'fail') {
    throw "Task $TaskId failed: $($record.failCode) $($record.failMsg)"
}

# --- Download results ----------------------------------------------------------
$resultUrls = @(($record.resultJson | ConvertFrom-Json).resultUrls)
if ($resultUrls.Count -eq 0) { throw "Task $TaskId succeeded but returned no resultUrls." }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$prefix = "$stamp`_$($TaskId.Substring(0, [Math]::Min(8, $TaskId.Length)))"
$web = New-Object System.Net.WebClient
$files = @()
for ($i = 0; $i -lt $resultUrls.Count; $i++) {
    $ext = [IO.Path]::GetExtension(([uri]$resultUrls[$i]).AbsolutePath)
    if (-not $ext) { $ext = '.png' }
    $path = Join-Path $OutDir "$prefix`_$($i + 1)$ext"
    $web.DownloadFile($resultUrls[$i], $path)
    $files += $path
}

# 'param' is a JSON string whose 'input' is itself a JSON string.
$param = $record.param
try { $param = $record.param | ConvertFrom-Json } catch { }
if ($param.input -is [string]) { try { $param.input = $param.input | ConvertFrom-Json } catch { } }
$durationSec = $null
if ($record.createTime -and $record.completeTime) {
    $durationSec = [Math]::Round(($record.completeTime - $record.createTime) / 1000, 1)
}
$meta = [ordered]@{
    taskId       = $TaskId
    model        = $record.model
    state        = $state
    durationSec  = $durationSec
    createTime   = $record.createTime
    completeTime = $record.completeTime
    param        = $param
    resultUrls   = $resultUrls
    files        = @($files | ForEach-Object { Split-Path $_ -Leaf })
}
[IO.File]::WriteAllText((Join-Path $OutDir "$prefix.json"), ($meta | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding $false))

Write-Host "Done in $durationSec s."
$files
