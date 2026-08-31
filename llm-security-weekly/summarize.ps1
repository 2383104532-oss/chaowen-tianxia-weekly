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

必须严格按下面的 Markdown 模板输出，标题层级、字段顺序、编号方式都不许改动。模板中「YYYY-MM-DD」替换为当天日期；占位内容（如标题、链接、要点）填充真实数据；某板块无数据时保留该板块标题并写明"本期未采集到"。

===== 输出模板（必须严格遵循）=====
# 大模型安全周报（YYYY-MM-DD）

> 数据收集时间：<generatedAt>（覆盖过去 <sinceDays> 天）

---

## 一、本周头条

### 1. <头条标题>
- **内容**：<摘要，结合数据中的热点>

## 二、GitHub 开源项目（本期采集 <N> 条）

### 🔥 近 30 天涨星最快
#### 1. [<项目名>](<url>) ⭐ <stars>（fast）
- **简介**：<描述>
- **要点**：<要点>
- **为什么值得关注**：<一句话>

### 🆕 本周新项目
#### 2. [<项目名>](<url>) ⭐ <stars>（new）
- **简介**：<描述>
- **要点**：<要点>
- **为什么值得关注**：<一句话>

## 三、大模型安全论文（本期采集 <N> 篇）

#### 1. [<标题>](<url>)（YYYY-MM-DD）
- **要点**：<摘要概括>
- **为什么值得关注**：<一句话>

## 四、英文安全新闻（本期采集 <N> 条）

#### 1. [<标题>](<url>)（YYYY-MM-DD）
- **来源**：<source>
- **要点**：<摘要>
- **为什么值得关注**：<一句话>

## 五、本周行动建议

1. <建议>
2. <建议>
3. <建议>

---

*本简报基于 YYYY-MM-DD 采集的公开数据自动生成，论文要点以原文为准。*
===== 模板结束 =====

其他要求：
- 使用简体中文编写；项目/论文/新闻标题保留英文原名。
- GitHub 项目：tag 为 "new" 归入"本周新项目"，tag 为 "fast" 归入"近 30 天涨星最快"；每类内编号续接。
- 每条必须有「要点」和「为什么值得关注」两个字段。
- 新闻标注发布日期（如 2026-08-30）。
- 只基于提供的原始数据，禁止编造；数据不足如实说明。
- 链接用 [标题](url) 格式。
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
  temperature = 0.3
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
