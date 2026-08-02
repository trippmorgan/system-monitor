#===============================================================================
# dj-hourly-comment.ps1 - Hourly Dr. Fever on-air commentary
#===============================================================================
# Asks the DJ server to improvise a line of between-songs patter (LLM when the
# jarvis superserver's Ollama is reachable, canned Fever lines otherwise),
# which lands in the dashboard chat, then cross-posts it to BotSpace so the
# rest of the network hears the Doctor too.
#
# Scheduled task: WPFQ-Fever-Hourly (register with -Install)
#===============================================================================
param([switch]$Install, [switch]$Uninstall)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogFile = Join-Path (Split-Path -Parent $ScriptDir) "logs\dj-commentary.log"
$BotSpaceUrl = if ($env:BOTSPACE_URL) { $env:BOTSPACE_URL } else { "http://100.80.111.84:4040" }
$DashboardUrl = "http://localhost:8787"
$TaskName = "WPFQ-Fever-Hourly"

function Log($msg) {
    "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg | Add-Content -Path $LogFile
}

if ($Install) {
    $action = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($MyInvocation.MyCommand.Path)`""
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date.AddMinutes(17) `
        -RepetitionInterval (New-TimeSpan -Hours 1)
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 12)
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
        -Settings $settings -Force | Out-Null
    Write-Host "Scheduled task '$TaskName' registered (hourly at :17)."
    exit 0
}

if ($Uninstall) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Scheduled task '$TaskName' removed."
    exit 0
}

# --- Generate commentary via the DJ server ---
try {
    $resp = Invoke-RestMethod -Uri "$DashboardUrl/api/dj/announce" -Method Post `
        -ContentType "application/json" -Body '{"generate": true}' -TimeoutSec 30
    $line = $resp.text
    Log "ANNOUNCE: $line"
} catch {
    Log "ERROR: DJ server announce failed: $($_.Exception.Message)"
    exit 1
}

# --- Cross-post to BotSpace (UTF-8 safe) ---
try {
    $payload = @{ agent_id = "drfever"; content = $line; severity = "info" } | ConvertTo-Json
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    Invoke-RestMethod -Uri "$BotSpaceUrl/api/post" -Method Post `
        -ContentType "application/json; charset=utf-8" -Body $bytes -TimeoutSec 15 | Out-Null
    Log "BOTSPACE: posted OK"
} catch {
    Log "WARN: BotSpace cross-post failed: $($_.Exception.Message)"
}

# --- Put the same line ON AIR as a TTS voice break ---
try {
    . (Join-Path (Split-Path -Parent $ScriptDir) "config.ps1")
    if ($PYTHON_EXE) {
        & $PYTHON_EXE (Join-Path $ScriptDir "dj-voice-break.py") $line 2>&1 | Out-Null
    }
} catch {
    Log "WARN: voice break failed: $($_.Exception.Message)"
}
