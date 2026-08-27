# collect.ps1 - Collect raw data: GitHub AI repos, LLM-security papers, security news.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File collect.ps1 [-SinceDays 7]
param([int]$SinceDays = 7)

$ErrorActionPreference = 'Continue'

# Force TLS 1.2 for all HTTPS calls (PS 5.1 may default to TLS 1.0)
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

$root   = $PSScriptRoot
$cfg    = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'config.json') | ConvertFrom-Json
$outDir = $cfg.outputDir
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$sinceDate = (Get-Date).AddDays(-$SinceDays).ToString('yyyy-MM-dd')
$paperSinceDate = (Get-Date).AddDays(-[int]$cfg.content.paperWindowDays).ToString('yyyy-MM-dd')
$stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$rawFile   = Join-Path $root "raw-$stamp.json"

$result = [ordered]@{
  generatedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  sinceDays   = $SinceDays
  github      = @()
  arxiv       = @()
  newsEn      = @()
  newsZh      = @()
}

$browserUA = @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36' }

# ---------------- GitHub (3 new this week + 2 fast risers in 30d) ----------------
$ghHeaders = @{ 'User-Agent' = 'weekly-report-bot'; 'Accept' = 'application/vnd.github+json' }
$since30Date = (Get-Date).AddDays(-30).ToString('yyyy-MM-dd')
$ghItems = @()
foreach ($q in @(
  @{ q = "created:>$sinceDate stars:>5";   tag = 'new' },
  @{ q = "created:>$since30Date stars:>50"; tag = 'fast' }
)) {
  try {
    $enc = [uri]::EscapeDataString($q.q)
    $url = "https://api.github.com/search/repositories?q=$enc&sort=stars&order=desc&per_page=50"
    $r = Invoke-RestMethod -Uri $url -Headers $ghHeaders -TimeoutSec 45
    foreach ($it in @($r.items)) {
      $it | Add-Member -NotePropertyName tag -NotePropertyValue $q.tag -Force
      $ghItems += $it
    }
    Write-Host "[github] query OK ($($r.items.Count) items): $($q.q) [$($q.tag)]"
  } catch {
    Write-Host "[github] query ERROR: $($_.Exception.Message)" -ForegroundColor Yellow
  }
  Start-Sleep -Milliseconds 1500   # respect search rate limit (10/min unauthenticated)
}
$pattern = $cfg.content.githubFilter
$filtered = @($ghItems |
  Where-Object { ($_.topics -join ' ') + ' ' + $_.description -match $pattern } |
  Group-Object full_name | ForEach-Object { $_.Group[0] })
$newItems = @($filtered | Where-Object { $_.tag -eq 'new' } |
  Sort-Object stargazers_count -Descending | Select-Object -First $cfg.content.githubNewCount)
$usedNames = @($newItems | ForEach-Object { $_.full_name })
$fastItems = @($filtered | Where-Object { $_.tag -eq 'fast' -and $usedNames -notcontains $_.full_name } |
  Sort-Object stargazers_count -Descending | Select-Object -First $cfg.content.githubFastCount)
$result.github = @($newItems + $fastItems | ForEach-Object {
  [ordered]@{
    name    = $_.full_name
    stars   = $_.stargazers_count
    url     = $_.html_url
    desc    = $_.description
    created = $_.created_at.Substring(0, 10)
    tag     = $_.tag
  }
})
Write-Host "[github] collected: $($result.github.Count) (new=$($newItems.Count), fast=$($fastItems.Count))"

# ---------------- Papers (multi-source fallback) ----------------
$arxivList = @()

function ConvertFrom-InvertedIndex($inv) {
  if (-not $inv) { return '' }
  $pos = @{}
  foreach ($prop in $inv.PSObject.Properties) {
    foreach ($p in @($prop.Value)) { $pos[[int]$p] = $prop.Name }
  }
  $words = @()
  foreach ($i in ($pos.Keys | Sort-Object)) { $words += $pos[$i] }
  return ($words -join ' ')
}

# 1) arXiv export API (https)
try {
  $seen = @{}
  foreach ($q in @($cfg.content.arxivQuery)) {
    try {
      $enc = [uri]::EscapeDataString($q)
      $u = "https://export.arxiv.org/api/query?search_query=$enc&sortBy=submittedDate&sortOrder=descending&start=0&max_results=40"
      $r = Invoke-RestMethod -Uri $u -Headers $browserUA -TimeoutSec 60
      Write-Host "[papers] arXiv API OK ($($r.entry.Count) entries)"
      foreach ($e in @($r.entry)) {
        $id = ([string]$e.id).Trim()
        if ($seen.ContainsKey($id)) { continue }
        $seen[$id] = $true
        $arxivList += $e
      }
    } catch {
      Write-Host "[papers] arXiv API query ERROR: $($_.Exception.Message)" -ForegroundColor Yellow
    }
  }
} catch {
  Write-Host "[papers] arXiv API ERROR: $($_.Exception.Message)" -ForegroundColor Yellow
}

# 2) Crossref (generous limits, no key). arXiv papers lack 'published' dates,
#    so query twice: arXiv DOI prefix via created-date, and general works via pub-date.
if ($arxivList.Count -eq 0) {
  foreach ($sq in @($cfg.content.paperSearches)) {
    $s = [uri]::EscapeDataString($sq)
    foreach ($variant in @(
      "filter=from-created-date:$paperSinceDate,prefix:10.48550",
      "filter=from-pub-date:$paperSinceDate"
    )) {
      try {
        $u = "https://api.crossref.org/works?query=$s&$variant&sort=published&order=desc&rows=25&select=DOI,title,abstract,published"
        $r = Invoke-RestMethod -Uri $u -Headers $browserUA -TimeoutSec 30
        $n = @($r.message.items).Count
        Write-Host "[papers] Crossref OK ($n results): $sq [$variant]"
        foreach ($item in @($r.message.items)) {
          $title = [string]($item.title | Select-Object -First 1)
          $abs = ([string]$item.abstract) -replace '<[^>]+>', ' ' -replace '\s+', ' '
          $dp = $item.published.'date-parts'
          $pub = if ($dp -and $dp[0]) { ($dp[0] -join '-') } else { '' }
          $url = if ($item.DOI) { "https://doi.org/$($item.DOI)" } else { '' }
          $arxivList += [PSCustomObject]@{
            id         = $url
            _title     = $title
            _published = $pub
            _summary   = $abs.Trim()
          }
        }
      } catch {
        Write-Host "[papers] Crossref query ERROR: $($_.Exception.Message)" -ForegroundColor Yellow
      }
      Start-Sleep -Milliseconds 800
    }
  }
}

# 3) Semantic Scholar (with 429 retry)
if ($arxivList.Count -eq 0) {
  try {
    $q = [uri]::EscapeDataString('LLM security prompt injection jailbreak')
    $u = "https://api.semanticscholar.org/graph/v1/paper/search?query=$q&fields=title,abstract,externalIds,publicationDate&limit=30&sort=publicationDate:desc"
    for ($attempt = 1; $attempt -le 3; $attempt++) {
      try {
        $r = Invoke-RestMethod -Uri $u -Headers $browserUA -TimeoutSec 40
        if ($r.data) {
          Write-Host "[papers] Semantic Scholar OK ($($r.data.Count) papers)"
          foreach ($d in $r.data) {
            $id = if ($d.externalIds.ArXiv) { "https://arxiv.org/abs/$($d.externalIds.ArXiv)" } else { '' }
            $arxivList += [PSCustomObject]@{
              id         = $id
              _title     = $d.title
              _published = $d.publicationDate
              _summary   = $d.abstract
            }
          }
        }
        break
      } catch {
        if ($_.Exception.Message -match '429|Too Many') {
          Write-Host "[papers] S2 rate-limited, retry $attempt/3 in 5s..." -ForegroundColor Yellow
          Start-Sleep -Seconds 5
        } else { throw }
      }
    }
  } catch {
    Write-Host "[papers] Semantic Scholar ERROR: $($_.Exception.Message)" -ForegroundColor Yellow
  }
}

# 4) OpenAlex
if ($arxivList.Count -eq 0) {
  try {
    foreach ($sq in @($cfg.content.paperSearches)) {
      try {
        $s = [uri]::EscapeDataString($sq)
        $u = "https://api.openalex.org/works?search=$s&filter=from_publication_date:$sinceDate&sort=publication_date:desc&per-page=25"
        $r = Invoke-RestMethod -Uri $u -Headers $browserUA -TimeoutSec 20
        Write-Host "[papers] OpenAlex OK ($($r.results.Count) results): $sq"
        foreach ($w in @($r.results)) {
          $url = if ($w.doi) { "https://doi.org/$($w.doi)" } elseif ($w.ids.openalex) { $w.ids.openalex } else { $w.id }
          $arxivList += [PSCustomObject]@{
            id         = $url
            _title     = $w.title
            _published = $w.publication_date
            _summary   = ConvertFrom-InvertedIndex $w.abstract_inverted_index
          }
        }
      } catch {
        Write-Host "[papers] OpenAlex query ERROR: $($_.Exception.Message)" -ForegroundColor Yellow
      }
      Start-Sleep -Milliseconds 800
    }
  } catch {
    Write-Host "[papers] OpenAlex ERROR: $($_.Exception.Message)" -ForegroundColor Yellow
  }
}

# 5) fallback: Hugging Face daily papers
if ($arxivList.Count -eq 0) {
  try {
    $hf = Invoke-RestMethod -Uri "https://huggingface.co/api/daily_papers?date=$sinceDate" -Headers $browserUA -TimeoutSec 20
    if ($hf) {
      Write-Host "[papers] HF daily papers OK ($($hf.Count) papers)"
      $kw = 'secur|safety|jailbreak|injection|alignment|red team|privacy|poison|guardrail|attack|defen|vulnerab|hallucinat|bias'
      foreach ($p in $hf) {
        $paper = $p.paper
        $text = "$($paper.title) $($paper.summary)"
        if ($text -match $kw) {
          $id = if ($paper.arxivId) { "https://arxiv.org/abs/$($paper.arxivId)" } else { $paper.url }
          $arxivList += [PSCustomObject]@{
            id         = $id
            _title     = $paper.title
            _published = $p.publishedAt
            _summary   = $paper.summary
          }
        }
      }
    }
  } catch {
    Write-Host "[papers] HF daily papers ERROR: $($_.Exception.Message)" -ForegroundColor Yellow
  }
}

# normalize + strong relevance-filter + date-validity check
$strongKw = $cfg.content.paperStrongKw
$llmKw    = $cfg.content.paperLlmKw
$secKw    = $cfg.content.paperSecKw
$preparedPapers = @()
$statTotal = 0; $statRelated = 0; $statDateOK = 0
foreach ($p in $arxivList) {
  if (-not $p.id) { continue }
  $statTotal++
  $t = if ($p._title) { [string]$p._title } elseif ($p.title) { ([string]$p.title -replace '\s+', ' ').Trim() } else { '' }
  $s = if ($p._summary) { [string]$p._summary } elseif ($p.summary) { ([string]$p.summary -replace '\s+', ' ').Trim() } else { '' }
  $text = "$t $s"
  # strong signal (only used in LLM-security context) OR (LLM-term AND security-term)
  $isRelated = ($text -match $strongKw) -or (($text -match $llmKw) -and ($text -match $secKw))
  if (-not $isRelated) { continue }
  $statRelated++
  # normalize date: yyyy / yyyy-M / yyyy-M-d -> yyyy-MM-dd (pad zeroes)
  $pubRaw = ([string]$p._published).Trim()
  $pub = ''
  if ($pubRaw -match '^(\d{4})-(\d{1,2})-(\d{1,2})$') {
    $pub = '{0:D4}-{1:D2}-{2:D2}' -f [int]$matches[1], [int]$matches[2], [int]$matches[3]
  } elseif ($pubRaw -match '^(\d{4})-(\d{1,2})$') {
    $pub = '{0:D4}-{1:D2}-01' -f [int]$matches[1], [int]$matches[2]
  } elseif ($pubRaw -match '^(\d{4})$') {
    $pub = "$pubRaw-01-01"
  } else { continue }
  try {
    $d = [datetime]::ParseExact($pub, 'yyyy-MM-dd', $null)
    if ($d -gt (Get-Date).AddDays(5) -or $d -lt (Get-Date).AddDays(-[int]$cfg.content.paperWindowDays)) { continue }  # future / outside window
  } catch { continue }
  $statDateOK++
  $preparedPapers += [PSCustomObject]@{
    id        = $p.id
    title     = $t
    published = $pub
    summary   = $s
  }
}
Write-Host "[papers] stats: total=$statTotal related=$statRelated dateOK=$statDateOK"
$result.arxiv = @($preparedPapers |
  Sort-Object published -Descending |
  Select-Object -First $cfg.content.arxivCount |
  ForEach-Object {
    [ordered]@{
      title     = ($_.title -replace '\s+', ' ').Trim()
      url       = ([string]$_.id).Trim()
      published = $_.published
      summary   = if ($_.summary.Length -gt 400) { $_.summary.Substring(0, 400) } else { $_.summary }
    }
  })
Write-Host "[papers] collected: $($result.arxiv.Count)"

# ---------------- News ----------------
function Get-FeedItems([string]$feedUrl) {
  try {
    $resp = Invoke-WebRequest -Uri $feedUrl -Headers $browserUA -TimeoutSec 25 -UseBasicParsing
    $content = $resp.Content
    # re-decode as UTF-8 from raw bytes to avoid mojibake (PS5.1 may use Latin-1)
    if ($resp.RawContentStream) {
      $ms = New-Object System.IO.MemoryStream
      $resp.RawContentStream.CopyTo($ms)
      $content = [Text.Encoding]::UTF8.GetString($ms.ToArray())
    }
    if ($content -match '<rss|<feed|<RDF') {
      $x = [xml]$content
      if ($x.rss.channel.item) { return @($x.rss.channel.item) }
      if ($x.feed.entry)       { return @($x.feed.entry) }
      if ($x.RDF.item)         { return @($x.RDF.item) }
      Write-Host "[news] $feedUrl : xml but no items" -ForegroundColor Yellow
    } else {
      Write-Host "[news] $feedUrl : not a feed (http $($resp.StatusCode), len=$($content.Length))" -ForegroundColor Yellow
    }
  } catch {
    Write-Host "[news] $feedUrl ERROR: $($_.Exception.Message)" -ForegroundColor Yellow
  }
  return @()
}

function Get-ItemLink($item) {
  $link = $item.link
  if ($link -is [System.Xml.XmlElement]) {
    if ($link.href) { return [string]$link.href }
    return ([string]$link.InnerText).Trim()
  }
  if ($link -is [System.Array]) {
    $l0 = $link | Select-Object -First 1
    if ($l0.href) { return [string]$l0.href }
    return ([string]$l0).Trim()
  }
  if ($link -is [System.Management.Automation.PSCustomObject]) { return $link.href }
  return ([string]$link).Trim()
}

function Get-ItemTitle($item) {
  $t = $item.title
  if ($t -is [System.Xml.XmlElement]) { $t = $t.InnerText }
  return (([string]$t) -replace '<[^>]+>', '').Trim()
}

# --- English RSS feeds ---
foreach ($f in @($cfg.content.feedsEn)) {
  $items = Get-FeedItems $f
  $matched = 0
  $sample = ''
  foreach ($it in $items) {
    $t = Get-ItemTitle $it
    if (-not $sample -and $t) { $sample = $t.Substring(0, [Math]::Min(40, $t.Length)) }
    if ($t -and $t -match $cfg.content.newsKeywordEn) {
      $matched++
      $result.newsEn += [ordered]@{ title = $t; url = Get-ItemLink $it; source = $f; pubDate = $it.pubDate }
    }
  }
  Write-Host "[news] EN $f : $($items.Count) items, $matched matched | sample: $sample"
}

# --- HN Algolia API (English, split queries) ---
try {
  $ts = [int64]((Get-Date).AddDays(-$SinceDays).ToUniversalTime() - [datetime]'1970-01-01').TotalSeconds
  $matched = 0
  foreach ($hq in @($cfg.content.hnQueries)) {
    $q = [uri]::EscapeDataString($hq)
    $u = "https://hn.algolia.com/api/v1/search_by_date?query=$q&tags=story&hitsPerPage=30&numericFilters=created_at_i%3E$ts"
    $r = Invoke-RestMethod -Uri $u -Headers $browserUA -TimeoutSec 25
    foreach ($h in @($r.hits)) {
      if ($h.title -and $h.title -match $cfg.content.newsKeywordEn) {
        $matched++
        $url = if ($h.url) { $h.url } else { "https://news.ycombinator.com/item?id=$($h.objectID)" }
        $result.newsEn += [ordered]@{ title = $h.title; url = $url; source = 'news.ycombinator.com'; pubDate = $h.created_at }
      }
    }
  }
  Write-Host "[news] HN Algolia : matched $matched"
} catch {
  Write-Host "[news] HN Algolia ERROR: $($_.Exception.Message)" -ForegroundColor Yellow
}

# --- Chinese RSS feeds ---
foreach ($f in @($cfg.content.feedsZh)) {
  $items = Get-FeedItems $f
  $matched = 0
  $sample = ''
  foreach ($it in $items) {
    $t = Get-ItemTitle $it
    if (-not $sample -and $t) { $sample = $t.Substring(0, [Math]::Min(40, $t.Length)) }
    if ($t -and $t -match $cfg.content.newsKeywordZh) {
      $matched++
      $result.newsZh += [ordered]@{ title = $t; url = Get-ItemLink $it; source = $f; pubDate = $it.pubDate }
    }
  }
  Write-Host "[news] ZH $f : $($items.Count) items, $matched matched | sample: $sample"
}

# --- dedup by url; freshness filter (last 7 days); date-desc; max 2/day + max 2/source ---
function Get-DayKey([string]$rawDate) {
  if (-not $rawDate) { return 'unknown' }
  try {
    $pd = [datetime]::Parse($rawDate, [Globalization.CultureInfo]::InvariantCulture)
    return $pd.ToString('yyyy-MM-dd')
  } catch { return 'unknown' }
}
function Select-News($items, [int]$max, [int]$maxPerDay = 2, [int]$maxPerSource = 2) {
  $dedup = @($items | Group-Object { $_['url'] } | ForEach-Object { $_.Group[0] })
  $cutoff = (Get-Date).AddDays(-7)
  $valid = @()
  foreach ($n in $dedup) {
    $day = Get-DayKey ([string]$n.pubDate)
    if ($day -eq 'unknown') { continue }
    try {
      $d = [datetime]::ParseExact($day, 'yyyy-MM-dd', $null)
      if ($d -ge $cutoff) { $valid += $n }
    } catch { }
  }
  $sorted = @($valid | Sort-Object { Get-DayKey ([string]$_.pubDate) } -Descending)
  $dayCount = @{}
  $srcCount = @{}
  $selected = @()
  foreach ($n in $sorted) {
    $day = Get-DayKey ([string]$n.pubDate)
    $src = [string]$n.source
    if (-not $dayCount.ContainsKey($day)) { $dayCount[$day] = 0 }
    if (-not $srcCount.ContainsKey($src)) { $srcCount[$src] = 0 }
    if ($dayCount[$day] -lt $maxPerDay -and $srcCount[$src] -lt $maxPerSource) {
      $dayCount[$day]++
      $srcCount[$src]++
      $selected += $n
    }
    if ($selected.Count -ge $max) { break }
  }
  return @($selected)
}
# English: single source (HN) -> don't cap per-source; relax per-day so we fill up to 8.
$result.newsEn = @(Select-News $result.newsEn $cfg.content.newsEnCount 99 99)
# Chinese: multi-source -> keep balanced caps (per-day 2, per-source 2)
$result.newsZh = @(Select-News $result.newsZh $cfg.content.newsZhCount 2 2)

Write-Host "[news] en=$($result.newsEn.Count) zh=$($result.newsZh.Count)"
$result | ConvertTo-Json -Depth 5 | Out-File -FilePath $rawFile -Encoding utf8
Write-Host "Saved raw data: $rawFile"
