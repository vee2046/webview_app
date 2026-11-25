# CLAUDE.md

Claude Code（claude.ai/code）在本仓库的操作指引。

**完整的协作规约与 SOP 见 [`AGENTS.md`](AGENTS.md)** —— 目录结构、常用命令、配置即契约的三份副本与四道闸门、分类/图标同步规则、自动更新链路、环境坑清单、视觉约定、收敛原则、提交前检查清单。

架构与决策全文见 [`docs/DESIGN.md`](docs/DESIGN.md)。

## 三条最要紧的

1. **只做修复与收敛**，不顺手开发新功能 / 新配置项 / 新开关（见 AGENTS.md §10）
2. **改了配置必须** `python3 scripts/sync-categories.py` → `./scripts/publish-config.sh`，并部署 kmlab_site
3. **出包用** `./scripts/build-android.sh`（自动递增版本号，并把 APK 拷到项目根目录）
