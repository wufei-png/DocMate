# 01 · 证据与授权

状态：已完成（2026-09-20）。优先级：P0。前置条件：无。

## 交付结果

DocMate 的普通文档问答维持现有流程。代码核验发现文档缺口后，gap report 能说明证据对应的仓库与版本，并准确区分已发布行为和本地开发状态。`auto` 继续完成高置信的小型文档修复及远端发布，但不会依据未提交或尚未发布的代码自行推送文档。`ask` 一次明确确认可以覆盖完整修复，窄授权只覆盖已说明的动作。

## 现有契约与修改入口

- `skills/docmate/SKILL.md`、`SKILL.en.md`、`SKILL.zh.md` 包含仓库选择、证据优先级、gap report、`ask/auto/off` 和修复流程；三个安装模板的行为须一致。
- 当前 gap report 有 doc/code 路径、目标文档和 confidence，没有 HEAD、ref、dirty 或代码是否已发布的说明。`auto` 由 agent 判定高置信、小型纯文档修复，后续流程可提交、推送并创建 PR/MR。
- `docs/configuration.md` 说明 catalog 与 update mode；`docs/update-workflow.md` 说明修复授权。`evals/golden-cases.jsonl` 和 `evals/run_forward_tests.py` 只检验抽象回答，不调用 agent；`tests/test_skill_content.py` 只检查 Skill 文本。
- 仓库文档、代码、catalog、issue、提交信息和 PR/MR 内容可提供证据，不能充当授权或改变执行策略。保留现有无版本号 catalog；本任务不更改其字段。

## 阶段

1. **证据来源与 `auto` 条件** — 在三份 Skill 中，仅对代码核验或修复路径要求记录 docs repo 和 related code repo 的路径、HEAD、ref、dirty 状态及与拟发布目标的关系；gap report 用短字段呈现。历史文档、生成输出和生成源按角色判断；生成关系不明时停止 `auto`。本地 dirty/untracked code 或仅 feature branch 存在的行为仍可用于带来源说明的回答，不能单独触发 `auto` 发布。更新相应契约文档和针对性 eval 反例。**依赖：** 无。**验收：** docs-only 问题不新增 Git 核验；dirty/unpublished 和生成关系不明的用例在规则中明确阻止 `auto`；三份 Skill 语义一致；运行 pytest 与 eval。一个本地提交。
2. **授权范围与不可信内容** — gap report 明确拟修改的文档，以及是否包含 edit、commit、push、PR/MR；`ask` 获得完整范围的一次确认后继续执行，用户只授权本地修改时停止于该范围。`off` 只报告；`auto` 仍遵循阶段 1 的条件。写清仓库内容不能产生授权事件。需要预览时只报告计划，在任何 Git write 或 push 前停止，不借用 `gh pr create --dry-run` 充当无副作用预览。同步三份 Skill、`docs/update-workflow.md` 和必要的测试/eval。**依赖：** 阶段 1。**验收：** 完整授权与窄授权的后续动作可区分；恶意文档指令不被视为授权；完整 pytest 和 eval 通过。一个本地提交。

## 验证与证据范围

仓库基线使用 `bash scripts/validate_catalog.sh skills/docmate/references/docmate.catalog.example.json`、`python3 evals/run_forward_tests.py` 和 pytest。若当前 Python 没有 pytest，已验证的替代命令为 `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 uv run --no-project --python 3.11 --with pytest pytest -q`。阶段提交前检查 staged diff；完成后运行全套适用检查及 `git diff --check`。

静态 Skill 测试与现有 eval 不能证明真实 agent 遵守授权，也不能证明 GitHub/GitLab 副作用。报告时区分这些证据。完成记录写入[执行队列](agent-first-queue.md)，并在本文记录阶段提交主题与检查结果。

## 完成记录

- 阶段 1 — `d502bbf docs: record evidence before auto repair`：三份 Skill 为代码核验和修复路径记录文档/代码仓库快照及发布关系；`auto` 阻止本地开发证据和未知生成关系；补充配置说明与证据反例 eval。
- 阶段 2 — `d22042f docs: scope repair authorization`：gap report 列出精确文档和 edit、commit、push、PR/MR 范围；`ask` 的完整/窄授权、`off`、不可信仓库内容和 preview 边界均写入三份 Skill、流程说明与 eval。
- 审查修复 — `40a2ebb docs: clarify local repair scope`：本地编辑在隔离 worktree 中进行但止于暂存、提交和发布之前；dirty/feature 与未知生成关系反例改为在 `auto` 模式下验证阻断。
- 检查：`bash scripts/validate_catalog.sh skills/docmate/references/docmate.catalog.example.json`（通过）；`python3 evals/run_forward_tests.py`（13 条用例有效）；`PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 uv run --no-project --python 3.11 --with pytest pytest -q`（51 passed）；`git diff --check`（通过）。系统 `python3` 3.14 没有安装 pytest，故使用计划指定的隔离 Python 3.11 回退命令。
- 审查：一名新的只读审查代理提出 2 项 P2；均已采纳并在 `40a2ebb` 修复后重新运行上述检查。
- 未验证：抽象 eval 和静态 Skill 测试不证明真实 agent 会遵守授权，也不证明 GitHub/GitLab 的 worktree、push 或 PR/MR 副作用；本任务未执行真实远端发布。
