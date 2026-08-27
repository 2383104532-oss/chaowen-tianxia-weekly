# send_email.ps1 - Send the latest weekly report via SMTP (QQ mail).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File send_email.ps1 [-ReportFile <path>]
param([string]$ReportFile)

$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$cfg  = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'config.json') | ConvertFrom-Json

if (-not $cfg.smtp.authCode -or $cfg.smtp.authCode -match 'YOUR_') {
  Write-Error 'smtp.authCode is not configured in config.json. Skipping email.'
  exit 1
}
if (-not $ReportFile) {
  $ReportFile = Get-ChildItem (Join-Path $cfg.outputDir 'weekly-llm-security-*.md') |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
  if (-not $ReportFile) { Write-Error 'No report found. Run summarize first.'; exit 1 }
}

$md = Get-Content -Raw -Encoding UTF8 $ReportFile

function ConvertTo-HtmlBody([string]$markdown) {
  $h = [System.Net.WebUtility]::HtmlEncode($markdown)
  $h = $h -replace '^### (.*)$', '<h3>$1</h3>'
  $h = $h -replace '^## (.*)$',  '<h2>$1</h2>'
  $h = $h -replace '^# (.*)$',   '<h1>$1</h1>'
  $h = $h -replace '\*\*(.+?)\*\*', '<strong>$1</strong>'
  $h = $h -replace '\[([^\]]+)\]\(([^)]+)\)', '<a href="$2" target="_blank">$1</a>'
  $h = $h -replace '`([^`]+)`', '<code>$1</code>'
  $h = $h -replace '^- ', '<li>'
  $h = $h -replace '\r?\n', '<br/>'
  return $h
}

$html = "<html><head><meta charset='utf-8'></head><body style='font-family:Microsoft YaHei, sans-serif;line-height:1.7;max-width:900px;margin:auto;padding:20px;color:#222;'>" +
        (ConvertTo-HtmlBody $md) + "</body></html>"

# Force TLS 1.2 (required by QQ SMTP; older .NET defaults to TLS 1.0)
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

$msg = New-Object Net.Mail.MailMessage
$msg.From = New-Object Net.Mail.MailAddress($cfg.smtp.from)
foreach ($t in @($cfg.smtp.to)) { $msg.To.Add($t) }
$msg.Subject        = "【大模型安全与开源周报】$(Get-Date -Format 'yyyy-MM-dd')"
$msg.IsBodyHtml     = $true
$msg.Body           = $html
$msg.BodyEncoding   = [Text.Encoding]::UTF8
$msg.SubjectEncoding = [Text.Encoding]::UTF8

function Send-Mail([int]$port, [bool]$ssl) {
  $client = New-Object Net.Mail.SmtpClient($cfg.smtp.server, $port)
  $client.EnableSsl   = $ssl
  $client.Timeout     = 60000
  $client.Credentials = New-Object Net.NetworkCredential($cfg.smtp.user, $cfg.smtp.authCode)
  $client.Send($msg)
  $client.Dispose()
}

function Show-ErrorChain($ex) {
  Write-Host "  detail: $($ex.Message)" -ForegroundColor Red
  $inner = $ex.InnerException
  while ($inner) {
    Write-Host "  inner : $($inner.GetType().Name): $($inner.Message)" -ForegroundColor Red
    $inner = $inner.InnerException
  }
}

try {
  Send-Mail -port $cfg.smtp.port -ssl $cfg.smtp.useSsl
  Write-Host "Email sent OK (port $($cfg.smtp.port)) to: $($cfg.smtp.to -join ', ')"
} catch {
  Write-Host "SMTP FAILED on port $($cfg.smtp.port): $($_.Exception.Message)" -ForegroundColor Red
  Show-ErrorChain $_.Exception

  # auto retry with 587 STARTTLS when 465 SSL failed
  if ($cfg.smtp.port -eq 465) {
    Write-Host "Retrying with port 587 (STARTTLS)..." -ForegroundColor Yellow
    try {
      Send-Mail -port 587 -ssl $true
      Write-Host "Email sent OK (port 587) to: $($cfg.smtp.to -join ', ')" -ForegroundColor Green
      exit 0
    } catch {
      Write-Host "SMTP FAILED on port 587: $($_.Exception.Message)" -ForegroundColor Red
      Show-ErrorChain $_.Exception
    }
  }

  Write-Host ''
  Write-Host 'TROUBLESHOOT:' -ForegroundColor Cyan
  Write-Host '  1. 报错含 535 / "Username and Password not accepted"：授权码错误或未开启 SMTP。请在 QQ 邮箱网页版 -> 设置 -> 账户 -> 开启 SMTP 服务，重新生成授权码，并更新 config.json 的 authCode。' -ForegroundColor Yellow
  Write-Host '  2. 报错含 SSL/TLS / 连接被关闭：网络或 TLS 问题，确认可访问 smtp.qq.com:465/587。' -ForegroundColor Yellow
  Write-Host '  3. 手动探测端口: Test-NetConnection smtp.qq.com -Port 465' -ForegroundColor Yellow
  exit 1
}
$msg.Dispose()
