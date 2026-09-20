# 03 · 安装与 catalog

状态：已完成（2026-09-20）。优先级：P1。前置条件：无功能依赖；[执行队列](agent-first-queue.md) 将其排在写入风险之后。

## 交付结果

非交互安装不再成功丢弃同名仓库，catalog 校验能阻止跨仓库的明确名称冲突，安装输出准确区分远端默认分支与本地 fallback，`--existing backup` 留下持久可读的用户配置备份。Catalog 仍使用当前 `defaults`/`repos` 格式，由 agent 在候选仓库之间判断语义匹配。

## 实施前入口与兼容范围

- `scripts/install.sh::resolve_duplicate_repo_names()` 在 `--yes` 或无 TTY 时保留第一个同名仓库、排除第二个并成功退出；交互安装已有 rename/use 选项。`tests/test_installer.py::test_duplicate_repo_names_keep_first_in_non_interactive_install` 固定了这个旧行为。
- `scripts/validate_catalog.sh` 分别检查精确重复的 name、path、alias，未检查一个仓库的 name 与另一个仓库的 alias 或大小写变体。`tests/test_catalog_validator.py` 有当前基础用例。
- `scripts/install.sh::detect_default_branch()` 先尝试 provider/remote，再回退 local HEAD 和 `main`。`tests/test_installer.py::test_installer_uses_local_head_when_remote_default_is_unavailable` 固定了该行为。候选分支的实际发布目标由修复流程在写入前重新核对，不能靠安装时的 fallback 作保证。
- `scripts/install.sh::ensure_backup_root()` 把旧安装移到 `${TMPDIR:-/tmp}/docmate-skill-backups`；系统可能清理该目录。`docs/install.md` 和现有 backup 测试需与新位置一致。
- 仓库当前 catalog 无 `schemaVersion`，也不支持 repo 级 update mode。安装器、validator、示例 catalog 和 Skill 继续使用现有字段；不迁移用户配置。

## 阶段

1. **同名仓库显式失败** — 在 `--yes`/无 TTY 下，两个不同 path 生成相同 catalog name 时非零退出，列出冲突和人工 rename/排除途径；旧安装目录在失败前不受影响。交互式 rename/use 继续可用。修改 `scripts/install.sh`、`tests/test_installer.py`。**依赖：** 无。**验收：** 显式 `--repo` 和自动扫描的重复名称都不会静默丢仓库；已安装 Skill 在失败后可读；针对性 installer tests 和完整 pytest 通过。一个本地提交。
2. **名称与 alias 冲突校验** — 在 `scripts/validate_catalog.sh` 中统一比较不同仓库的 name 和 alias；使用 Unicode NFKC 加小写作为可实现的近似规范化，涵盖 name↔alias 与大小写冲突。同一仓库自己复用名称不构成跨仓库冲突。扩充 `tests/test_catalog_validator.py`，不新增 schema 字段。**依赖：** 阶段 1。**验收：** 冲突 catalog 失败并指出两个仓库；合法示例和现有 catalog 用例通过；完整 pytest 通过。一个本地提交。
3. **分支来源准确呈现** — 在 `scripts/install.sh` 的远端探测失败路径明确标注 local HEAD 或 `main` 是未验证候选，不能输出“已探测远端默认分支”；`README.md`、`docs/configuration.md`、`docs/install.md` 使用相同表述。保留 `baseBranchCandidates` 格式与 QA 安装能力；修复前仍须重新核对远端。更新远端不可达、feature branch 和无 remote 的 installer tests。**依赖：** 阶段 2。**验收：** 输出和文档均不把 fallback 称为远端事实；旧 catalog 仍有效；完整 pytest 通过。一个本地提交。
4. **持久备份位置** — `--existing backup` 默认使用 `${XDG_STATE_HOME:-$HOME/.local/state}/docmate/backups`，保持 backup/skip/overwrite 的选择语义，并在失败或完成时输出备份路径。更新 `tests/test_installer.py` 与 `docs/install.md`。**依赖：** 阶段 3。**验收：** 备份中的 catalog、Skill 可读；失败后路径可定位；完整 pytest、catalog 示例校验、eval 与 `git diff --check` 通过。一个本地提交。

## 验证与剩余范围

基线命令：`bash scripts/validate_catalog.sh skills/docmate/references/docmate.catalog.example.json`、`python3 evals/run_forward_tests.py`、pytest。缺少 pytest 时可用 `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 uv run --no-project --python 3.11 --with pytest pytest -q`。计划撰写时记录的旧基线为 50 passed、6 个 eval 用例；本次实施前重新核对为 53 passed、15 个 eval 用例。

持久备份不等于事务式升级：安装中断仍需按输出恢复。该任务不改变既有 catalog 字段或宿主 skill 路径。完成记录写入[执行队列](agent-first-queue.md)，并在本文记录阶段提交主题与检查结果。

## 完成记录

- `47fe0ef` `Fail non-interactive installs on duplicate repository names`：显式仓库和自动扫描的同名仓库在安装目标变动前失败。
- `52a0203` `Validate normalized catalog names across repositories`：跨仓库 name/alias 使用 NFKC 加小写检查。
- `0405f90` `Label fallback base branches as unverified candidates`：安装输出与文档区分远端默认分支和本地候选。
- `f6ec3d7` `Store install backups in persistent user state`：备份移至用户 state 目录，失败后输出路径。
- `fdee051` `Preflight normalized repository names before installation`：采纳独立 review 的 P1 发现；安装器在移动旧 Skill 前拦截规范化后同名的仓库。

验证：完整 pytest 66 passed；示例 catalog 校验 `OK`；forward eval 15 例通过；`bash -n` 和 `git diff --check` 通过。系统 `python3` 未安装 pytest，使用计划中的 `uv run --no-project --python 3.11 --with pytest` 执行。

未验证：真实宿主平台安装、远端 provider 探测和安装中断后的人工恢复流程；持久备份仍不提供事务式升级。
