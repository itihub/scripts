# 🚀 我的自定义脚本集合 (My Custom Scripts Collection)

这个仓库汇集了我日常工作和学习中使用的各种自定义 Bash 脚本。它们主要用于自动化重复性任务、优化开发环境、以及简化 WSL (Windows Subsystem for Linux) 的配置和使用。

## 🎯 仓库目的

* **自动化：** 减少手动操作，提高效率。
* **环境一致性：** 跨不同 WSL 实例或 Linux 环境快速设置和同步个人配置。
* **可维护性：** 有组织地管理脚本，方便查找、更新和分享。
* **版本控制：** 利用 Git 追踪脚本的历史变更，确保安全和可回溯。

## 📁 目录结构

本仓库的脚本按照功能和用途进行了分类，以下是主要的目录结构和说明：

-   `bin/`: 存放可以直接作为命令运行的脚本。通常会将此目录添加到 `$PATH` 环境变量中。
    -   **示例：** `proxy-setup` (WSL 代理设置脚本), `git-aliases` (Git 辅助命令)。
-   `lib/`: 存放被其他脚本调用的辅助函数库或通用代码片段。这些文件通常不直接运行。
    -   **示例：** `common.sh` (通用 Bash 函数), `network_utils.sh` (网络工具函数)。
-   `config/`: 存放需要被 `source` 到 Shell 环境中的配置文件或环境变量定义。
    -   **示例：** `bash_aliases.sh` (Bash 别名), `env_vars.sh` (通用环境变量)。
-   `tools/`: 存放与特定工具或平台（如 Docker, Kubernetes, Cloud CLI 等）相关的辅助脚本。
-   `dev/`: 存放开发流程相关的辅助脚本（如项目初始化、构建、测试）。
-   `backup/`: 存放用于数据备份或同步的脚本。
-   `README.md`: 本说明文件。
-   `.gitignore`: Git 忽略文件配置。

## 🚀 如何使用

### 1. 克隆仓库

首先，将本仓库克隆到您的 WSL 或 Linux 家目录下，建议放在 `~/scripts/`：

```bash
git clone [https://github.com/itihub/scripts.git](https://github.com/itihub/scripts.git) ~/scripts
