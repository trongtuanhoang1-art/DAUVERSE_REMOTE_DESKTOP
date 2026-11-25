param(
    [Parameter(Mandatory = $true)][string]$ProjectId,
    [Parameter(Mandatory = $true)][string]$TaskName,
    [ValidateSet("BUILD", "QA", "RENDER", "POWERSHELL")][string]$JobKind = "BUILD",
    [Parameter(Mandatory = $true)][string]$CommandToRun
)

$ErrorActionPreference = "Stop"
$StartUtc = (Get-Date).ToUniversalTime()

Write-Host "[DAUVERSE JOB WRAPPER] Starting $JobKind job '$TaskName' for $ProjectId..."
$OutputLines = & powershell -NoProfile -Command $CommandToRun 2>&1 | Out-String
$ExitCode = $LASTEXITCODE
if ($null -eq $ExitCode) { $ExitCode = 0 }

$NowUtc = (Get-Date).ToUniversalTime()
$IssuedMs = [int64]([DateTimeOffset]$NowUtc).ToUnixTimeMilliseconds()
$EventId = [guid]::NewGuid().ToString()
$Nonce = [guid]::NewGuid().ToString("N")
$Timestamp = $NowUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
$DeviceId = $env:COMPUTERNAME

if ($ExitCode -eq 0) {
    $EventType = switch ($JobKind) {
        "QA"     { "QA_PASSED" }
        "RENDER" { "RENDER_COMPLETED" }
        default  { "BUILD_SUCCEEDED" }
    }
    $Status = "COMPLETED"
    $Severity = "SUCCESS"
} else {
    $EventType = if ($JobKind -eq "QA") { "QA_FAILED" } else { "BUILD_FAILED" }
    $Status = "FAILED"
    $Severity = "HIGH"
}

function ConvertTo-SerdeJsonScalar {
    param($Val)
    if ($null -eq $Val) { return "null" }
    if ($Val -is [bool]) { return $(if ($Val) { "true" } else { "false" }) }
    if ($Val -is [int] -or $Val -is [int64]) { return $Val.ToString([System.Globalization.CultureInfo]::InvariantCulture) }
    $s = [string]$Val
    $sb = [System.Text.StringBuilder]::new($s.Length + 8)
    [void]$sb.Append('"')
    foreach ($ch in $s.ToCharArray()) {
        $code = [int][char]$ch
        switch ($code) {
            0x22 { [void]$sb.Append('\"') }
            0x5C { [void]$sb.Append('\\') }
            0x08 { [void]$sb.Append('\b') }
            0x0C { [void]$sb.Append('\f') }
            0x0A { [void]$sb.Append('\n') }
            0x0D { [void]$sb.Append('\r') }
            0x09 { [void]$sb.Append('\t') }
            default {
                if ($code -lt 0x20) {
                    [void]$sb.AppendFormat('\u{0:x4}', $code)
                } else {
                    [void]$sb.Append($ch)
                }
            }
        }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

$Secret = $env:DAUVERSE_EVENT_HMAC_KEY
if (-not [string]::IsNullOrEmpty($Secret) -and $Secret.Length -ge 16) {
    $SummaryText = "$JobKind job '$TaskName' exited with code $ExitCode"
    $BadgeText = "ExitCode=$ExitCode"
    $ProgressJson = if ($ExitCode -eq 0) { '"100.0000"' } else { "null" }
    $ConfidenceJson = '"1.0000"'

    $ProvJson = "[" + ((@(
        (ConvertTo-SerdeJsonScalar "APPROVED_WRAPPER_ADAPTER"),
        (ConvertTo-SerdeJsonScalar $true),
        (ConvertTo-SerdeJsonScalar ([int]$ExitCode)),
        (ConvertTo-SerdeJsonScalar $BadgeText)
    )) -join ",") + "]"

    $Canonical = "[" + ((@(
        (ConvertTo-SerdeJsonScalar "DAUVERSE_AI_EVENT_V2"),
        "2",
        (ConvertTo-SerdeJsonScalar ([int64]$IssuedMs)),
        (ConvertTo-SerdeJsonScalar $Nonce),
        (ConvertTo-SerdeJsonScalar $EventId),
        (ConvertTo-SerdeJsonScalar $Timestamp),
        (ConvertTo-SerdeJsonScalar "powershell_job"),
        (ConvertTo-SerdeJsonScalar $DeviceId),
        (ConvertTo-SerdeJsonScalar $ProjectId),
        (ConvertTo-SerdeJsonScalar $TaskName),
        (ConvertTo-SerdeJsonScalar $TaskName),
        (ConvertTo-SerdeJsonScalar $EventType),
        (ConvertTo-SerdeJsonScalar $Status),
        (ConvertTo-SerdeJsonScalar $Severity),
        $ProgressJson,
        (ConvertTo-SerdeJsonScalar $SummaryText),
        "null",
        $ConfidenceJson,
        $ProvJson
    )) -join ",") + "]"

    $Hmac = [System.Security.Cryptography.HMACSHA256]::new([System.Text.Encoding]::UTF8.GetBytes($Secret))
    $SigBytes = $Hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Canonical))
    $SigHex = -join ($SigBytes | ForEach-Object { $_.ToString("x2") })

    $BodyObj = [ordered]@{
        schema_version = 2
        event = [ordered]@{
            event_id = $EventId
            timestamp = $Timestamp
            source = "powershell_job"
            device_id = $DeviceId
            project_id = $ProjectId
            task_id = $TaskName
            task_name = $TaskName
            event_type = $EventType
            status = $Status
            severity = $Severity
            progress = if ($ExitCode -eq 0) { 100.0 } else { $null }
            summary = $SummaryText
            artifact_reference = $null
            confidence = 1.0
            provenance = [ordered]@{
                adapter_type = "APPROVED_WRAPPER_ADAPTER"
                evidence_verified = $true
                exit_code = $ExitCode
                evidence_badge = $BadgeText
            }
        }
        issued_at_ms = $IssuedMs
        nonce = $Nonce
        signature_hex = $SigHex
    } | ConvertTo-Json -Depth 6

    $Endpoint = if ($env:DAUVERSE_EVENT_ENDPOINT) { $env:DAUVERSE_EVENT_ENDPOINT } else { "http://127.0.0.1:21188/v1/events" }
    try {
        Invoke-RestMethod -Uri $Endpoint -Method Post -ContentType "application/json; charset=utf-8" -Body ([System.Text.Encoding]::UTF8.GetBytes($BodyObj)) -TimeoutSec 2 | Out-Null
    } catch {
        Write-Verbose "DAUVERSE loopback bridge unreachable; continuing."
    }
}

exit $ExitCode
