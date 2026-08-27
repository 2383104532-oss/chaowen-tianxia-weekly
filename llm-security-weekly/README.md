# 大模型安全与开源周报 · 自动化工作流

每周自动采集 **GitHub AI/大模型热门项目 + arXiv 大模型安全论文 + 中英文安全新闻**，
由 LLM 生成中文周报（Markdown），并通过 QQ 邮箱 SMTP 发送。

## 目录结构

```
llm-security-weekly\
├── config.json        # 所有配置：邮箱、LLM API、内容数量、关键词、RSS 源
├── collect.ps1        # 采集：GitHub API + arXiv API + RSS → raw-<时间戳>.json
├── summarize.ps1      # 摘要：调用 LLM API 生成中文周报 Markdown
├── send_email.ps1     # 发送：QQ SMTP 发送周报邮件（正文为 HTML）
├── run_weekly.ps1     # 总入口：采集 → 摘要 → 发邮件（含日志）
└── README.md
```

周报输出到 `<你的路径>\weekly-reports\`，运行日志追加到 `weekly-reports\run.log`。

## 首次配置（一次性）

1. **编辑 `config.json`**：
   - `smtp.user` / `smtp.from`：填你的 QQ 邮箱地址
   - `smtp.authCode`：QQ 邮箱授权码（非登录密码）。获取：QQ 邮箱 → 设置 → 账户 → 开启 SMTP → 生成授权码
   - `smtp.to`：收件人邮箱数组，可多个
   - `llm.apiKey`：DeepSeek API Key（https://platform.deepseek.com/ 申请）
   - 如换 OpenAI：改 `llm.provider/model/baseUrl`
   - `content.*`：各板块数量、关键词、RSS 源，可按需调整

2. **手动跑一次验证**（建议按顺序逐步验证，确认无误后再注册定时任务）：
   - ① 最快验证授权码是否可用：用示例周报发一封测试邮件
     ```powershell
     powershell -NoProfile -ExecutionPolicy Bypass -File <你的路径>\llm-security-weekly\send_email.ps1 -ReportFile "<你的路径>\weekly-reports\weekly-llm-security-2026-08-26.md"
     ```
   - ② 验证采集（生成 `raw-<时间戳>.json`，输出各板块数量）：
     ```powershell
     powershell -NoProfile -ExecutionPolicy Bypass -File <你的路径>\llm-security-weekly\collect.ps1
     ```
   - ③ 验证摘要（调用 DeepSeek 生成新周报 Markdown）：
     ```powershell
     powershell -NoProfile -ExecutionPolicy Bypass -File <你的路径>\llm-security-weekly\summarize.ps1
     ```
   - ④ 一键全流程（采集 → 摘要 → 发邮件，日志在 `weekly-reports\run.log`）：
     ```powershell
     powershell -NoProfile -ExecutionPolicy Bypass -File <你的路径>\llm-security-weekly\run_weekly.ps1
     ```

## 注册 Windows 定时任务（每周一 08:00）

> ⚠️ 需要**管理员权限**（普通 PowerShell 会被拒绝访问）。注册任务后建议在"任务计划程序"里确认"使用最高权限运行"或至少以当前用户运行。

### 方式 A：在 **cmd.exe（管理员）** 中执行

```bat
schtasks /Create /F /TN "LLM-Security-Weekly" /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"<你的路径>\llm-security-weekly\run_weekly.ps1\"" /SC WEEKLY /D MON /ST 08:00
```

### 方式 B：在 **PowerShell（管理员）** 中执行

```powershell
$action  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument '-NoProfile -ExecutionPolicy Bypass -File "<你的路径>\llm-security-weekly\run_weekly.ps1"'
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 8am
Register-ScheduledTask -TaskName "LLM-Security-Weekly" -Action $action -Trigger $trigger -Force
```

其他命令：
- 手动运行：`schtasks /Run /TN "LLM-Security-Weekly"`
- 查看状态：`schtasks /Query /TN "LLM-Security-Weekly" /V /FO LIST`
- 删除任务：`schtasks /Delete /TN "LLM-Security-Weekly" /F`

## 说明与限制

- **论文来源自动降级**：优先 arXiv API；网络不可达时自动切换 Crossref 学术数据库（`api.crossref.org`，免 key、限额宽松），
  仍按关键词（LLM security / prompt injection / jailbreak / LLM safety）+ 近 7 天过滤，条目带 DOI 链接。
- **英文新闻**：主要来自 Hacker News（hn.algolia.com，拆 4 个关键词查询）+ RSS 源。
- **中文新闻**：FreeBuf / 嘶吼 RSS（已修复 XML 编码与标题提取）。
- 中文新闻源 RSS 可能不稳定或为空，此时周报会如实标注"本期未采集到"；
  可在 `content.feedsZh` 中增删 RSS 源。
- 本机执行环境（AI 会话沙箱）无外网，脚本需在**普通 PowerShell（非沙箱）**下运行才能联网；
  定时任务由 Windows 计划程序直接运行，不受此限制。
- LLM 摘要要求 `llm.apiKey` 有效；未配置时 summarize 会跳过，只产出原始数据存档。
- 邮件正文为简单 Markdown→HTML 转换，表格/复杂格式可能不完美。
