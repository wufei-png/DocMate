# 02 · 修复与发布

状态：已完成（2026-09-20）。优先级：P0。前置条件：[01 · 证据与授权](01-evidence-authorization.md) 已完成；已按当前 Skill 核对其契约。

## 交付结果

DocMate 在明确 docs repo、目标文档、base 和 push remote 后，用独立 worktree 完成纯文档修复。成功时清理安全的临时资源；失败时留下可识别的 branch、commit 或 patch，供 agent 恢复。发布前后查询 GitHub PR/GitLab MR 状态，避免对已知同一 branch/base 盲目重复创建。

## 实施前入口与执行边界（历史基线）

以下记录任务开始时的状态；当前修复契约以三份 Skill 和 `docs/update-workflow.md` 为准。

- `skills/docmate/SKILL.md`、`SKILL.en.md`、`SKILL.zh.md` 是需同步的行为契约。实施前 `docs/update-workflow.md` 示例固定 `/tmp/docmate-worktree`，用 `git remote | head -n 1` 选择 push remote，随后直接 push 和 create。
- Catalog 的 `repos[].baseBranchCandidates` 是候选，不证明它对应远端默认分支。`scripts/install.sh` 目前可能从 local HEAD 或字面量 `main` 生成候选。修复时须依据当前远端状态重新核对目标；`auto` 遇到不明或不匹配的 base 停止并报告，明确选定非默认 base 的用户授权可以进入 `ask` 流程。
- `auto` 保留端到端发布，仅限高置信、小型纯文档修复，且不能依赖未提交或尚未发布的代码行为。`ask` 的授权范围由 gap report 说明；只获本地修改授权时不能发布。
- 修复继续由 agent 使用 Git、`gh`、`glab` 原生命令执行。Git worktree 的增删由 `git worktree` 管理，用户主工作区的改动不被清理、stash 或 reset。

## 阶段

1. **目标核查与 worktree 生命周期** — 在写入前确认 docs repo、目标文档、push remote/provider、候选 base 是否存在于该 remote、base 与远端默认分支的关系，以及当前授权。用唯一目录和不冲突 branch，从明确的 base SHA 建立 worktree；重新检查缺口与路径边界，只暂存意图中的文档文件。无 patch 或已确认成功且 clean 时用 `git worktree remove`；有未提交 patch、已提交未推送或远端结果不明时保留 worktree，输出路径、branch、commit 和恢复步骤。替换 `docs/update-workflow.md` 的固定路径/隐式 remote 示例，并同步三份 Skill。**依赖：** 01 完成。**验收：** 临时 Git 仓库演练正常、主工作区 dirty、base 不明、branch 冲突和中断路径；主工作区内容与 HEAD 不变；安全清理与保留路径清楚；pytest 通过。一个本地提交。
2. **远端对账与发布恢复** — 显式选择项目与 push remote。push 前查询同名远端 branch：查询失败不能视为不存在，SHA 不同时停止，不 force push。恢复已知修复先复用原 branch/worktree；按 repo、head、base 查询 open PR/MR，查询成功且无匹配时才 create。create 成功或结果不明后再次查询；仍不明时保留已知现场并报告，不盲重试。避免 CLI 隐式 fork/push，GitHub 创建时显式指定 `--head`；预览停在任何 Git write/push 之前。同步三份 Skill、工作流文档及必要的 README/eval。**依赖：** 阶段 1。**验收：** 用当前 `gh`/`glab` help 核对命令参数；临时 bare Git repo 演练远端 branch 相同/冲突；模拟已存在 review、查询失败和 create 结果不明；完整 pytest、eval、`git diff --check` 通过。一个本地提交。

## 验证与恢复界限

可用的本地检查为 `python3 evals/run_forward_tests.py`、catalog 示例校验和 pytest；缺少 pytest 时可用 `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 uv run --no-project --python 3.11 --with pytest pytest -q`。本地演练只证明所示 Git/CLI 命令与文档契约；现有 eval 不运行 agent。没有真实授权的远端沙箱时，不宣称已验证宿主执行或远端 PR/MR 行为。

原生命令流程可以识别已知 branch 上的重试，不能提供机器级 exactly-once 保证。没有可核对的远端结果时停下并报告。完成记录写入[执行队列](agent-first-queue.md)，并在本文记录阶段提交主题与检查结果。

## 完成记录

- 阶段 1 — `4cb90f9 docs: verify repair target and preserve worktree state`：三份 Skill 和工作流文档明确 push remote、远端 base/default/SHA、唯一 worktree、路径与暂存边界，以及清理/保留条件。临时 Git 仓库演练 dirty 主工作区、缺失 base、分支冲突、中断后的 dirty worktree 和 clean 移除；主工作区 HEAD 与内容不变。阶段检查：pytest 52 passed。
- 阶段 2 — `dfb915d docs: reconcile remote reviews before publish`：加入远端分支 SHA 对账、push 后复查、精确 open PR/MR 查询和 create 后再查询；同步 README、三份 Skill、工作流和 eval。核对本机 `gh` 2.101.0 与 `glab` 1.117.0 help；bare remote 演练分支不存在、相同、冲突和查询失败；模拟已有 review、查询失败、create 结果不明。阶段检查：pytest 53 passed，eval 15 例有效，catalog 示例校验通过，`git diff --check` 通过。
- 审查修复 — `e5534c2 docs: stop cross-project repair publication`：只读审查指出已确认 fork 仍会使用同项目创建参数，可能选错源分支；核实后明确停止跨项目/fork 发布。审查无其他 P0-P3 发现。修复后 pytest 53 passed、eval 15 例有效、catalog 示例校验及 diff 检查通过。

未验证：eval 只检查抽象案例格式/预期，不运行 agent；模拟查询不证明真实 GitHub/GitLab API 行为。本次未使用远端授权沙箱，没有执行真实 PR/MR 创建或宿主端到端流程。原生命令对已知 branch/review 的恢复不提供机器级 exactly-once 保证；跨项目/fork 发布会停止并报告。
