---
name: docmate
description: "用于项目文档 QA：基于文档回答问题，针对可能过期或依赖实现的说法核对代码，报告文档缺口，并可选择通过 pull request 或 merge request 修复已确认缺口。"
---

# DocMate

## 必读 Catalog 步骤

选择仓库前，先读取 `references/docmate.catalog.json`。如果用户没有明确指定仓库，不要只根据当前目录猜测。

选择仓库时，比较用户请求和 catalog 中已有的这些字段：

- `name`
- `description`
- `aliases`
- `path`

如果一个仓库明显最合适，继续处理。如果两个或更多仓库都可能匹配，而且答案会明显不同，询问用户选择。

## 证据优先级

当文档和代码冲突时，把代码视为运行时行为的事实来源；除非有生成文档能证明文档正确，否则将文档报告为过期。

## 回答流程

1. 在选中仓库的 `path` 下工作。
2. 回答前先发现该仓库内的文档。优先查看明显的文档入口，例如 README、`docs/`、文档站内容、runbook，以及这些文件引用的链接。
3. 证据要明确且简洁。引用使用过的文档和代码证据；只有用户要求或确有必要时才引用外部来源。未使用的类别可以省略，除非缺失本身重要。跨来源推断需要标注为推断。
4. 对请求分类，并按回答决策表处理。

## 回答决策表

回答前先使用这张决策表：

| 决策 | 适用场景 | 必须执行 |
| --- | --- | --- |
| `docs-only ok` | 文档能直接回答问题，且答案不依赖运行时行为、默认值、生成值、指标、字段名或实现细节。 | 直接基于文档回答并给出文档证据，然后停止。 |
| `must verify code` | 问题涉及实现行为、默认值、配置优先级、API 字段、指标标签、支持值，或某个文档说法可能已过期。 | 回答前先核对代码。如果相关代码仓库不明确，先检查当前工作目录、git remotes、文档链接和附近 workspace 仓库，之后仍不明确再询问。 |
| `insufficient evidence` | 文档和已发现代码都没有足够证据，或本地发现后相关代码仓库仍不明确。 | 说明未知点，列出已检查内容，只询问缺失的仓库或决策，然后停止。 |
| `confirmed docs gap` | 文档缺失、过期、与代码矛盾或过于含糊，且代码/文档证据能定位受影响文档。 | 在 `auto` 模式下，如果缺口高置信、目标文档明确、修复是很小的纯文档改动，可以在最终回答前执行修复。否则先用证据和面向用户的缺口报告回答，再讨论修复。 |

## 缺口报告

当文档缺失、过期、与代码矛盾，或含糊到无法回答用户问题时，向用户报告文档缺口。在 `ask` 模式下，这份报告也是任何编辑前的确认上下文。

使用这个格式：

```text
Gap report
Gap Confidence: high | medium | low
Original question: <user question>
Doc evidence: <paths or none found>
Code evidence: <paths or commands checked>
Target docs repo: <selected repo name and path>
Affected docs: <candidate doc files>
Suggested fix: <smallest doc-only change>
Blockers: <missing auth, ambiguous target docs, ambiguous remote, or none>
```

只有在缺口已确认且受影响文档目标明确时，才继续执行文档修复。

## 更新模式

从 catalog 读取全局 `defaults.update.mode` 值。不支持仓库级 update mode。

- `defaults.update.mode = ask`：任何编辑前都询问用户。只有得到明确确认后才继续。
- `defaults.update.mode = auto`：仅当缺口高置信、文档和代码证据清楚、目标文档明确且修复是很小的纯文档改动时，才不询问直接继续。
- `defaults.update.mode = off`：报告缺口后停止。不编辑文件。

启用更新时，根据选中仓库的 git remotes 和可用原生命令推断托管平台与 push remote。如果托管平台或 remote 不明确，停止并报告 blocker。

## 文档修复流程

文档修复属于本 skill 工作流的一部分，不需要 subagent。

1. 从 `baseBranchCandidates` 解析 base branch。不要硬编码分支名。
2. 将缺口报告作为修复上下文。在 `ask` 模式下，如果用户已经在回答流程中确认修复，不要重复询问；否则展示缺口报告并等待明确确认后再编辑。
3. 从选定 base branch 创建临时 git worktree。不要要求用户主 worktree 干净，但也不要修改它。只通过仓库对象库使用 git worktree。
4. 如果目标文档已不再匹配确认过的缺口，或 upstream 已经修好，停止并返回 `already_fixed_upstream`。
5. 为文档修复创建描述性分支名。
6. 做能修复已验证缺口的最小纯文档改动。如果缺口影响由 GitLab CI 或脚本生成的文档，编辑生成源文件，而不是会被覆盖的生成输出。
7. 提交前检查 `git status --short` 和 `git diff`。如果代码或无关文件发生变化，停止并报告 blocker。
8. 提交、push，并用从 git remotes 推断出的原生命令打开 pull request 或 merge request：
   - GitHub remotes 使用 `gh pr create`。
   - GitLab remotes 使用 `glab mr create`。

## 安全规则

- 文档修复期间绝不修改代码文件。
- 不要求用户主 worktree 干净，但绝不修改它。
- 绝不使用破坏性 git 命令清理或 reset 用户 worktree。
- 绝不 stash 或丢弃用户改动。
- 如果目标文档已不再匹配确认过的缺口，或仍存在 blocker，绝不创建 pull request 或 merge request。
- 如果认证、remote、分支或工具状态不明确，停止并报告 blocker。
