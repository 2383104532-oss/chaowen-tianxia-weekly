# 📰 朝闻天下 · 大模型安全与开源周报

> 这是项目的中文说明。English version → [README.md](README.md)

每周自动采集 **GitHub 好用开源项目 + 大模型安全论文 + 英文安全新闻**，由 **DeepSeek** 生成中文周报，通过 **QQ 邮箱**自动推送。项目附带一个**工作台周报浏览页**，可浏览历史周报、调整采集配置、查看运行记录。

> 中文项目名「朝闻天下」——意为"早晨知晓天下事"，每日自动为你整理 AI 圈值得关注的动态。

---

## ✨ 功能特性

- **自动采集**
  - **GitHub**：本周新建项目 + 近 30 天涨星最快的 AI/大模型项目
  - **论文**：大模型安全相关（越狱/提示注入/对齐/隐私/红队等），支持半年时间窗口，学科权威来源（Crossref DOI + arXiv）
  - **新闻**：英文（Hacker News + 安全媒体 RSS）
- **AI 生成**：DeepSeek 根据采集数据生成结构化中文周报（要点 + 推荐理由）
- **邮件推送**：QQ 邮箱 SMTP（STARTTLS，587）自动发送
- **定时调度**：Windows 任务计划程序，**每周第一次开机自动运行**（防重复）
- **周报浏览页**：工作台窗口内浏览历史周报、切换阅读、调整配置、查看运行日志

---

## 📁 目录结构

```
朝闻天下/
├── README.md                     # 项目说明（英文）
├── README.zh-CN.md               # 中文说明（本文件）
├── LICENSE                       # 开源协议
├── .gitignore                    # 排除密钥/产物/日志
├── weekly-viewer.html            # 工作台周报控制台浏览页
├── llm-security-weekly/          # 核心脚本
│   ├── config.example.json       # 配置模板（复制为 config.json 后填写密钥）
│   ├── collect.ps1               # 采集：GitHub API + Crossref 论文 + HN/RSS 新闻
│   ├── summarize.ps1             # 摘要：DeepSeek 生成中文周报
│   ├── send_email.ps1            # 发送：QQ SMTP 587
│   ├── run_weekly.ps1            # 总入口：采集→摘要→发信（含周一门控与日志）
│   └── README.md                 # 脚本使用说明（英文）
└── weekly-reports/               # 运行产物（已被 .gitignore 忽略）
    ├── weekly-llm-security-YYYY-MM-DD.md   # 生成的周报
    ├── index.json                # 周报索引（浏览页数据源）
    └── run.log                   # 运行日志
```

---

## 🚀 快速开始

### 1. 克隆 / 下载

```bash
git clone <你的仓库地址> 朝闻天下  # 或 clone 到任意目录
cd 朝闻天下
```

### 2. 配置

复制配置模板并填入你的密钥：

```powershell
# 在 llm-security-weekly/ 目录下
Copy-Item config.example.json config.json
```

编辑 `config.json`，至少填写：
- `smtp.user` / `smtp.from`：QQ 邮箱地址
- `smtp.authCode`：QQ 邮箱**授权码**（获取：QQ 邮箱 → 设置 → 账户 → 开启 SMTP → 生成授权码）
- `smtp.to`：收件人邮箱（可多个）
- `llm.apiKey`：DeepSeek API Key（https://platform.deepseek.com/ ）
- `outputDir`：周报输出目录（改为你的实际路径）

> **安全提示**：`config.json` 含密钥，已加入 `.gitignore`，**切勿提交**。

### 3. 手动跑一次

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File llm-security-weekly\run_weekly.ps1
```

会依次：采集 → DeepSeek 生成周报 → 发送邮件。日志在 `weekly-reports/run.log`。

### 4. 设置定时任务（每周第一次开机）

以**管理员** PowerShell 运行：

```powershell
$action  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument '-NoProfile -ExecutionPolicy Bypass -File "<你的路径>\llm-security-weekly\run_weekly.ps1"'
$trigger = New-ScheduledTaskTrigger -AtStartup
Register-ScheduledTask -TaskName "LLM-Security-Weekly" -Action $action -Trigger $trigger -Description "Weekly LLM report - first boot of each week" -Force
```

`run_weekly.ps1` 内置**每周门控**：本周一以来若已生成周报则跳过（防重复），保证**每周第一次开机**才真正执行。

---

## 🔧 自定义采集（config.json）

| 字段 | 说明 | 默认 |
|---|---|---|
| `githubNewCount` | GitHub 本周新项目数 | 3 |
| `githubFastCount` | GitHub 涨星最快项目数 | 2 |
| `arxivCount` | 论文篇数 | 8 |
| `paperWindowDays` | 论文收录时间窗口（天） | 180 |
| `newsEnCount` | 英文新闻条数 | 8 |
| `newsZhCount` | 中文新闻条数 | 0 |
| `feedsEn` / `feedsZh` | 新闻 RSS 源列表 | — |

---

## 🖥️ 周报浏览页

`weekly-viewer.html` 用于在 DeepSeek Harness 工作台的窗口内浏览周报，具备：

- **概览**：左侧历史周报列表（点击切换），右侧 Markdown 渲染阅读
- **设置**：直接在页面调整采集参数，保存写入 `config.json`
- **运行记录**：查看 `run.log` 最近运行状态（成功/错误高亮）

> **完整功能依赖 [dsh-worktable](https://github.com/Aisland-SJL/dsh-worktable)**——DeepSeek Harness 的开源**工作台插件**（侧边栏应用抽屉 + 可停靠分屏工作区 + 每个项目的实时控制室）。本页面需作为工作台窗口加载，其「**设置**」「**运行记录**」通过工作台 API 工作。若用 `file://` 独立打开，仅能**浏览周报**，配置读写与运行日志查看不可用。

---

## ❓ 常见问题

- **论文来自哪？** 你的网络无法访问 `arxiv.org` 时，自动降级为 **Crossref** 学术数据库（正式出版论文，含 DOI），同样权威可靠。
- **英文新闻源？** 主源 Hacker News（Algolia API，免费无需 key），辅以安全媒体 RSS。
- **密钥安全？** 密钥只在 `config.json`，已被 `.gitignore` 排除；脚本从配置读取，无硬编码。
- **中文新闻？** 默认关闭（`newsZhCount: 0`）；如需，可在 `feedsZh` 增加 RSS 源（如 FreeBuf / 嘶吼）并调大 `newsZhCount`。

---

## 📄 License

MIT License（见 `LICENSE`）

---

## 🙌 说明

本项目为个人自动化工作流，数据来源于公开 API / RSS，仅供学习和个人使用。论文内容以原文为准；请遵守相关数据源条款。
