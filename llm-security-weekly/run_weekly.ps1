# run_weekly.ps1 - Full weekly pipeline: collect -> summarize -> send email.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File run_weekly.ps1
$ErrorActionPreference = 'Continue'

$root   = $PSScriptRoot
$logDir = Join-Path (Split-Path $root -Parent) 'weekly-reports'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$log = Join-Path $logDir 'run.log'
$ts  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

# --- gate: run only on the FIRST boot of the week (no report generated this week yet) ---
$thisMonday = (Get-Date).Date.AddDays(-(([int](Get-Date).DayOfWeek + 6) % 7))
$ranThisWeek = @(Get-ChildItem (Join-Path $logDir 'weekly-llm-security-*.md') -ErrorAction SilentlyContinue |
  Where-Object {
    $fn = $_.BaseName -replace '^weekly-llm-security-', ''
    try { [datetime]::ParseExact($fn, 'yyyy-MM-dd', $null) -ge $thisMonday } catch { $false }
  }).Count -gt 0
if ($ranThisWeek) {
  Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm')] Report already generated this week - skip."
  exit 0
}

function Write-Log([string]$line) {
  "$ts $line" | Out-File -Append -Encoding utf8 $log
  Write-Host $line
}

Write-Log '===== weekly run start ====='

# 1) Collect
$rawFile = ''
try {
  $out = & (Join-Path $root 'collect.ps1') 2>&1
  $out | ForEach-Object { Write-Log ($_.ToString()) }
  $rawFile = Get-ChildItem (Join-Path $root 'raw-*.json') |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
} catch {
  Write-Log "COLLECT FAILED: $($_.Exception.Message)"
}
if (-not $rawFile) { Write-Log 'ABORT: no raw data collected.'; exit 1 }

# 2) Summarize (LLM API)
$reportFile = ''
try {
  $out = & (Join-Path $root 'summarize.ps1') -RawFile $rawFile 2>&1
  $out | ForEach-Object { Write-Log ($_.ToString()) }
  # summarize.ps1 prints the report path as its last stdout line
  $reportFile = [string]($out | Select-Object -Last 1)
} catch {
  Write-Log "SUMMARIZE FAILED: $($_.Exception.Message)"
}
if (-not $reportFile -or -not (Test-Path $reportFile)) {
  # fall back: latest report in output dir
  $reportFile = Get-ChildItem (Join-Path $logDir 'weekly-llm-security-*.md') |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if ($reportFile) {
  Write-Log "Report: $reportFile"
} else {
  Write-Log 'WARN: no report produced this run.'
}

# 3) Send email
if ($reportFile) {
  try {
    $out = & (Join-Path $root 'send_email.ps1') -ReportFile $reportFile 2>&1
    $out | ForEach-Object { Write-Log ($_.ToString()) }
  } catch {
    Write-Log "EMAIL FAILED: $($_.Exception.Message)"
  }
}

Write-Log '===== weekly run end ====='
