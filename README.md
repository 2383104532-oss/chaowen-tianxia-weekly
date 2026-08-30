# 📰 Chaowen Tianxia · LLM Security & Open Source Weekly

Automatically curate, every week, the **top open-source projects, LLM-security papers, and English security news**, then let **DeepSeek** generate a structured **Chinese weekly report** delivered to you via **QQ Email**. The project also ships a **worktable weekly-viewer page** to browse past reports, tweak collection settings, and inspect run logs.

> **"朝闻天下 (Chaowen Tianxia)"** — "Learn what's happening in the world every morning." This project auto-archives the week's AI-security highlights into a concise report, so you catch 20+ curated items in 5 minutes and never miss a key LLM-security development.

---

## ✨ Features

- **Automated collection**
  - **GitHub**: new projects this week + fastest-growing AI/LLM projects in the last 30 days
  - **Papers**: LLM-security related (jailbreak / prompt injection / alignment / privacy / red team…), with a 6-month window, from the authoritative Crossref (DOI) / arXiv sources
  - **News**: English (Hacker News + security-media RSS)
- **AI generation**: DeepSeek turns the collected data into a structured Chinese weekly report (key points + why it matters)
- **Email delivery**: QQ Mail SMTP (STARTTLS, 587) — auto-sent
- **Scheduled runs**: Windows Task Scheduler — **runs at the first boot of each week** (with dedup)
- **Weekly-viewer page**: browse history, switch reports, adjust config, and view run logs inside the worktable pane

---

## 📁 Structure

```
chaowen-tianxia/
├── README.md                     # Project overview (this file)
├── README.zh-CN.md               # 中文说明（Chinese version）
├── LICENSE                       # MIT
├── .gitignore                    # excludes secrets / artifacts / logs
├── weekly-viewer.html            # worktable weekly-report console page
├── llm-security-weekly/          # core scripts
│   ├── config.example.json       # config template (copy to config.json, fill secrets)
│   ├── collect.ps1               # collect: GitHub API + Crossref papers + HN/RSS news
│   ├── summarize.ps1             # summarize: DeepSeek generates the Chinese report
│   ├── send_email.ps1            # send: QQ SMTP 587 (HTML body)
│   ├── run_weekly.ps1            # entry: collect -> summarize -> email (weekly gate + log)
│   └── README.md                 # scripts usage (detailed)
└── weekly-reports/               # runtime artifacts (git-ignored)
    ├── weekly-llm-security-YYYY-MM-DD.md   # generated weekly report
    ├── index.json                # report index (viewer data source)
    └── run.log                   # run log
```

---

## 🚀 Quick Start

### 1. Clone

```bash
git clone <your-repo-url> chaowen-tianxia
cd chaowen-tianxia
```

### 2. Configure

Copy the template and fill in your secrets:

```powershell
# inside llm-security-weekly/
Copy-Item config.example.json config.json
```

Edit `config.json` — at minimum set:
- `smtp.user` / `smtp.from`: your QQ email address
- `smtp.authCode`: QQ mail **app password** (QQ Mail → Settings → Account → enable SMTP → generate app password)
- `smtp.to`: recipient email(s)
- `llm.apiKey`: DeepSeek API key (https://platform.deepseek.com/ )
- `outputDir`: your report output directory

> **Security**: `config.json` contains secrets and is git-ignored — **never commit it**.

### 3. Run Once

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File llm-security-weekly\run_weekly.ps1
```

It will: collect → DeepSeek generates the report → send email. Logs go to `weekly-reports/run.log`.

### 4. Schedule (first boot of each week)

Run in an **admin** PowerShell:

```powershell
$action  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument '-NoProfile -ExecutionPolicy Bypass -File "<your-path>\llm-security-weekly\run_weekly.ps1"'
$trigger = New-ScheduledTaskTrigger -AtStartup
Register-ScheduledTask -TaskName "LLM-Security-Weekly" -Action $action -Trigger $trigger -Description "Weekly LLM report - first boot of each week" -Force
```

`run_weekly.ps1` has a built-in **weekly gate**: it skips if a report was already generated since this Monday (dedup), so it actually runs **only on the first boot of each week**.

---

## 🔧 Customization (config.json)

| Field | Description | Default |
|---|---|---|
| `githubNewCount` | GitHub new-project count | 3 |
| `githubFastCount` | GitHub fastest-growing count | 2 |
| `arxivCount` | paper count | 8 |
| `paperWindowDays` | paper time window (days) | 180 |
| `newsEnCount` | English news count | 8 |
| `newsZhCount` | Chinese news count | 0 |
| `feedsEn` / `feedsZh` | news RSS feed lists | — |

---

## 🖥️ Weekly-Viewer Page

`weekly-viewer.html` is used inside a DeepSeek Harness worktable pane:

- **Overview**: left = past reports (click to switch); right = rendered Markdown
- **Settings**: tune collection params in the page; saved back to `config.json`
- **Run log**: view recent `run.log` status (success/error highlighted)

> **Full functionality requires [dsh-worktable](https://github.com/Aisland-SJL/dsh-worktable)**, the open-source **workbench plugin for DeepSeek Harness** (sidebar app drawer + dockable split workspace + per-project control room). The page is meant to be loaded as a worktable pane, where its **Settings** and **Run-log** tabs work through the worktable APIs. Opening the file directly (`file://`) still lets you **browse reports**, but config read/write and run-log viewing are disabled.

---

## ❓ FAQ

- **Where do papers come from?** If your network can't reach `arxiv.org`, it auto-falls back to **Crossref** (published papers with DOI), equally authoritative.
- **English news source?** Mainly Hacker News (Algolia API, free, no key), plus security-media RSS.
- **Secrets safe?** Secrets live only in `config.json` (git-ignored); scripts read from config, no hardcoding.
- **Chinese news?** Disabled by default (`newsZhCount: 0`); to enable, add RSS feeds to `feedsZh` and raise `newsZhCount`.

---

## 📄 License

MIT License (see `LICENSE`)

---

## 🙌 Notes

This is a personal automation workflow. Data comes from public APIs / RSS and is for study & personal use only. Paper content follows the original; please respect the respective data-source terms.
