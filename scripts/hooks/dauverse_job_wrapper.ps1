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

$Secret = $env:DAUVERSE_EVENT_HMAC_KEY
if (-not [string]::IsNullOrEmpty($Secret) -and $Secret.Length -ge 16) {
    $Canonical = "DAUVERSE_AI_EVENT_V1|$EventId|$Timestamp|powershell_job|$DeviceId|$ProjectId|$TaskName|`"$EventType`"|`"$Status`"|$IssuedMs|$Nonce"
    $Hmac = [System.Security.Cryptography.HMACSHA256]::new([System.Text.Encoding]::UTF8.GetBytes($Secret))
    $SigBytes = $Hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Canonical))
    $SigHex = -join ($SigBytes | ForEach-Object { $_.ToString("x2") })

    $BodyObj = @{
        event = @{
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
            summary = "$JobKind job '$TaskName' exited with code $ExitCode"
            artifact_reference = $null
            confidence = 1.0
            provenance = @{
                adapter_type = "APPROVED_WRAPPER_ADAPTER"
                evidence_verified = $true
                exit_code = $ExitCode
                evidence_badge = "ExitCode=$ExitCode"
            }
        }
        issued_at_ms = $IssuedMs
        nonce = $Nonce
        signature_hex = $SigHex
    } | ConvertTo-Json -Depth 6

    $Endpoint = if ($env:DAUVERSE_EVENT_ENDPOINT) { $env:DAUVERSE_EVENT_ENDPOINT } else { "http://127.0.0.1:21188/v1/events" }
    try {
        Invoke-RestMethod -Uri $Endpoint -Method Post -ContentType "application/json" -Body $BodyObj -TimeoutSec 2 | Out-Null
    } catch {
        Write-Verbose "DAUVERSE loopback bridge unreachable; continuing."
    }
}

exit $ExitCode
