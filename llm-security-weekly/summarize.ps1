# summarize.ps1 - Generate the weekly Chinese report Markdown via LLM API.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File summarize.ps1 [-RawFile <path>]
param([string]$RawFile)

$ErrorActionPreference = 'Stop'

# Force TLS 1.2 (PS 5.1 may default to TLS 1.0)
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

$root = $PSScriptRoot
$cfg  = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'config.json') | ConvertFrom-Json

if (-not $cfg.llm.apiKey -or $cfg.llm.apiKey -match 'YOUR_') {
  Write-Error 'llm.apiKey is not configured in config.json. Skipping summary.'
  exit 1
}
if (-not $RawFile) {
  $RawFile = Get-ChildItem (Join-Path $root 'raw-*.json') |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
  if (-not $RawFile) { Write-Error 'No raw data found. Run collect.ps1 first.'; exit 1 }
}

$raw = Get-Content -Raw -Encoding UTF8 $RawFile | ConvertFrom-Json

$system = @'
你是一位资深的大模型安全（AI Security）研究员和开源社区观察者，负责撰写每周中文简报。

写作要求：
- 使用简体中文撰写，项目/论文/新闻标题保留英文原名；
- 结构清晰，包含：本周头条、GitHub 开源项目、大模型安全论文、英文新闻、本周行动建议；
- GitHub 项目中 tag 为 "new" 的标注为"本周新项目"，tag 为 "fast" 的标注为"近30天涨星最快"；
- 新闻条目在标题后标注发布日期（用 pubDate 字段，格式如 2026-08-25）；
- 每条内容给出"要点"和"为什么值得关注"；
- 只基于提供的原始数据撰写，禁止编造不存在的细节；某个板块数据为空或不足时如实说明"本期采集到 N 条"；
- 论文要点基于标题与摘要概括，并在文末注明"以原文为准"；
- 输出完整 Markdown，链接用 [标题](url) 格式。
'@

$user = @"
【数据收集时间】$($raw.generatedAt)（覆盖过去 $($raw.sinceDays) 天）
【GitHub AI/大模型项目】$(($raw.github | ConvertTo-Json -Depth 5 -Compress))
【大模型安全论文】$(($raw.arxiv | ConvertTo-Json -Depth 5 -Compress))
【英文安全新闻】$(($raw.newsEn | ConvertTo-Json -Depth 5 -Compress))

请据此生成一份完整的中文周报（Markdown 格式，含标题与日期）。
"@

$body = @{
  model       = $cfg.llm.model
  messages    = @(
    @{ role = 'system'; content = $system },
    @{ role = 'user';   content = $user }
  )
  temperature = 0.7
} | ConvertTo-Json -Depth 6

$headers = @{
  'Authorization' = "Bearer $($cfg.llm.apiKey)"
  'Content-Type'  = 'application/json; charset=utf-8'
}

# Send as explicit UTF-8 bytes: PS 5.1 encodes a string Body with ANSI/GBK,
# whose bytes can break JSON (some Chinese chars contain 0x5C).
$bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
$resp = Invoke-WebRequest -Uri $cfg.llm.baseUrl -Method Post -Headers $headers -Body $bodyBytes -TimeoutSec 300 -UseBasicParsing
# Re-decode the response as UTF-8: PS 5.1 decodes JSON responses with Latin-1 by default -> mojibake
$resp.RawContentStream.Position = 0
$ms = New-Object System.IO.MemoryStream
$resp.RawContentStream.CopyTo($ms)
$respText = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
$json = $respText | ConvertFrom-Json
$markdown = $json.choices[0].message.content

$date    = Get-Date -Format 'yyyy-MM-dd'
$outFile = Join-Path $cfg.outputDir "weekly-llm-security-$date.md"
$markdown | Out-File -FilePath $outFile -Encoding utf8
Write-Host "Report saved: $outFile"

# --- refresh weekly-reports/index.json (JSONP) for the worktable viewer ---
try {
  $idx = @()
  foreach ($f in @(Get-ChildItem (Join-Path $cfg.outputDir 'weekly-llm-security-*.md') | Sort-Object Name -Descending)) {
    $c = [string](Get-Content -Raw -Encoding UTF8 $f.FullName)
    $d = $f.BaseName -replace '^weekly-llm-security-', ''
    $t = if ($c -match '(?m)^# (.+)$') { $matches[1].Trim() } else { $f.BaseName }
    $idx += [ordered]@{ name = $f.Name; date = $d; title = $t; content = $c }
  }
  $json = $idx | ConvertTo-Json -Depth 3
  [System.IO.File]::WriteAllText((Join-Path $cfg.outputDir 'index.json'), "window.__REPORTS__ = $json;", (New-Object System.Text.UTF8Encoding($false)))
  Write-Host "Reports index refreshed: $($idx.Count) reports"
} catch {
  Write-Host "index refresh skipped: $($_.Exception.Message)"
}

Write-Output $outFile
