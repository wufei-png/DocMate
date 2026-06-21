# DocMate：给 Agent 用的文档 QA 和修复助手

DocMate 面向已经在用 Agent 的项目。它让 Agent 先从项目文档回答问题；碰到默认值、配置项、指标字段、接口行为这类容易过期的内容，再去代码里核对。发现文档缺失或和代码不一致时，DocMate 会产出带证据的 gap report，并按配置决定是否修文档。

它不是文档站，也不需要常驻服务。安装后，本地会有一个 agent-readable skill 和一份 `docmate.catalog.json`。Agent 需要处理项目文档问题时，按 skill 里的规则走。

## 它解决什么问题

团队文档常见的问题不是“没有”，而是少一步更新：README 没跟上安装脚本，配置默认值改了但文档没改，指标标签和代码里的名字对不上。开发者最后只能在 README、docs、源码和 issue 之间来回翻。

DocMate 把这件事收成几步：

1. 先读项目文档并回答。
2. 问题涉及实现细节时，查相关代码确认。
3. 文档缺失、过期或含糊时，输出 gap report，写清文档证据、代码证据、影响文件和置信度。
4. 用户确认后修复；如果全局模式是 `auto`，高置信的小范围问题可以直接修。

## 工作方式

### 用 skill 约束 Agent 行为

DocMate 的核心是一份 skill。里面写清楚 Agent 怎么选仓库、先看哪些文档、什么时候必须看代码、怎么判断文档缺口，以及修复时如何控制范围。

安装流程支持 OpenClaw、Claude Code、OpenCode、Codex 和 Hermes。全局和自定义安装都使用 `~/.agents/skills/docmate`，避免每个平台放一份不同的规则。

### 用 catalog 找项目

DocMate 用 `docmate.catalog.json` 记录项目路径、别名、描述和修复基线。安装时可以手动添加仓库，也可以扫描一个仓库前缀目录：

```bash
bash scripts/install.sh --yes --auto-scan --scan-root /absolute/path/to/repo-prefix --scan-depth 2
```

扫描结果会写入 catalog。之后用户用自然语言提问，Agent 会根据项目名、路径、别名和描述选择仓库，再进入仓库查文档和代码。

### 修复放在临时 worktree

DocMate 不要求主工作区干净，也不会直接在用户正在写代码的 checkout 里改文档。需要修复时，它会基于配置的 base branch 创建临时 git worktree，在临时目录完成最小文档改动，然后检查 `git status` 和 `git diff`。

修复完成后，DocMate 用 `gh` 打开 GitHub PR，或用 `glab` 打开 GitLab MR。主工作区里的实验代码、未提交修改和临时文件不会被这条流程碰到。

### 修复模式可以调

DocMate 支持三种全局修复模式：

- `ask`：默认模式。报告文档缺口后等待用户确认。
- `auto`：仅对高置信、目标文档明确、改动范围很小的问题自动修复。
- `off`：只报告问题，不修改文档。

`ask` 适合团队仓库，`auto` 适合个人项目或低风险文档，`off` 适合只想做诊断的场景。

### 安装

从 GitHub 安装：

```bash
curl -fsSL https://raw.githubusercontent.com/wufei-png/DocMate/main/scripts/install.sh | bash
```

安装器只安装 DocMate skill、生成 catalog，并把 skill 暴露给选定的 Agent 平台。它不会改主 Agent prompt、workspace identity 文件或 memory 文件。

## 适合什么项目

- 文档和代码经常一起变。
- 希望 Agent 回答时能给出文档和代码证据。
- 想发现文档缺口，但不想让 Agent 改主工作区。
- 同一台机器上有多个 Agent，需要共用一套文档 QA 规则。
- 文档修复要走 PR 或 MR，而不是停在聊天记录里。

## 简短总结

DocMate 做的事很窄：让 Agent 先读文档，再按需查代码；发现缺口后，给出证据，必要时在隔离 worktree 里修文档并开 PR/MR。它更像一套可安装的文档工作规则，而不是新的文档平台。
