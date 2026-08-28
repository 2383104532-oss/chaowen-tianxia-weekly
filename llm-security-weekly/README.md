# LLM Security Weekly · Automation Workflow

Automatically collect **GitHub AI/LLM trending projects + LLM-security papers + English security news** every week, have an LLM generate a Chinese weekly report (Markdown), and send it via QQ Mail SMTP.

## Structure

```
llm-security-weekly\
├── config.json        # all config: email, LLM API, counts, keywords, RSS feeds
├── collect.ps1        # collect: GitHub API + Crossref + HN/RSS -> raw-<timestamp>.json
├── summarize.ps1      # summarize: call LLM API to generate the Chinese report Markdown
├── send_email.ps1     # send: QQ SMTP (HTML body)
├── run_weekly.ps1     # entry: collect -> summarize -> email (with log)
└── README.md
```

Reports go to `<your-path>\weekly-reports\`; the run log appends to `weekly-reports\run.log`.

## First-time Setup (one-off)

1. **Edit `config.json`**:
   - `smtp.user` / `smtp.from`: your QQ email address
   - `smtp.authCode`: QQ Mail app password (not your login password). Get it: QQ Mail → Settings → Account → enable SMTP → generate app password
   - `smtp.to`: recipient email array (can be multiple)
   - `llm.apiKey`: DeepSeek API key (https://platform.deepseek.com/ )
   - To switch to OpenAI: change `llm.provider/model/baseUrl`
   - `content.*`: section counts, keywords, RSS feeds — adjust as needed

2. **Run once to verify** (step by step, then register the scheduled task):
   - ① Fastest: verify the app password by sending a test email with an existing report
     ```powershell
     powershell -NoProfile -ExecutionPolicy Bypass -File <your-path>\llm-security-weekly\send_email.ps1 -ReportFile "<your-path>\weekly-reports\weekly-llm-security-2026-08-26.md"
     ```
   - ② Verify collection (produces `raw-<timestamp>.json`, prints section counts):
     ```powershell
     powershell -NoProfile -ExecutionPolicy Bypass -File <your-path>\llm-security-weekly\collect.ps1
     ```
   - ③ Verify summarization (DeepSeek generates a new report Markdown):
     ```powershell
     powershell -NoProfile -ExecutionPolicy Bypass -File <your-path>\llm-security-weekly\summarize.ps1
     ```
   - ④ One-shot full pipeline (collect -> summarize -> email; log in `weekly-reports\run.log`):
     ```powershell
     powershell -NoProfile -ExecutionPolicy Bypass -File <your-path>\llm-security-weekly\run_weekly.ps1
     ```

## Register a Windows Scheduled Task (first boot of each week)

> ⚠️ Needs **admin rights** (a normal PowerShell will be denied). After registering, confirm in Task Scheduler to run with highest privileges or at least as the current user.

### Option A: in **cmd.exe (admin)**

```bat
schtasks /Create /F /TN "LLM-Security-Weekly" /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"<your-path>\llm-security-weekly\run_weekly.ps1\"" /SC WEEKLY /D MON /ST 08:00
```

### Option B: in **PowerShell (admin)**

```powershell
$action  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument '-NoProfile -ExecutionPolicy Bypass -File "<your-path>\llm-security-weekly\run_weekly.ps1"'
$trigger = New-ScheduledTaskTrigger -AtStartup
Register-ScheduledTask -TaskName "LLM-Security-Weekly" -Action $action -Trigger $trigger -Force
```

Other commands:
- Run manually: `schtasks /Run /TN "LLM-Security-Weekly"`
- Show status: `schtasks /Query /TN "LLM-Security-Weekly" /V /FO LIST`
- Delete task: `schtasks /Delete /TN "LLM-Security-Weekly" /F`

## Notes & Limits

- **Paper source auto-fallback**: prefers arXiv API; falls back to Crossref (`api.crossref.org`, no key, generous limits) when unreachable, filtering by keywords (LLM security / prompt injection / jailbreak / LLM safety) with a recent window; items carry DOI links.
- **English news**: mainly Hacker News (hn.algolia.com, 4 keyword queries) + RSS feeds.
- **Chinese news**: FreeBuf / 嘶吼 RSS (XML encoding & title extraction fixed).
- Chinese RSS feeds may be unstable or empty — the report will then honestly note "no items collected this week"; add/remove feeds in `content.feedsZh`.
- The AI sandbox has no external network; scripts must run in a **normal PowerShell (not sandbox)** to reach the network; the scheduled task runs directly via Task Scheduler, unaffected.
- LLM summarization requires a valid `llm.apiKey`; if unconfigured, summarize is skipped and only the raw data archive is produced.
- The email body is a simple Markdown→HTML conversion; tables / complex formatting may be imperfect.
