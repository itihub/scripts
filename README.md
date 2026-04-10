# 🚀 Ops Toolbox & Scripts Collection (运维与自动化脚本库)

这个仓库汇集了我日常工作、学习中沉淀的各项自动化运维资产。从基础的 Linux/WSL 环境初始化，到完全幂等的企业级中间件离线编译安装，再到 Docker 容器化编排与 Python 辅助工具，旨在打造一个全场景覆盖的个人 DevOps 工具箱。

## 🎯 仓库目的

- **极致自动化：** 将复杂且容易出错的手动配置（如源码编译、依赖解决）转化为一键式脚本，提升效率。
- **高可用与便携：** 安装脚本内置“离线绿色包”支持与“完全幂等”特性，无论在线还是断网内网环境，都能瞬间完成部署接管。
- **环境一致性：** 跨物理机、虚拟机或 WSL 实例快速同步全局代理、软件源等基础运行环境。
- **架构规范化：** 严格遵循代码与配置分离、文档与脚本隔离的最佳实践，方便长期维护、升级和知识库分享。

## 📁 核心目录结构

本仓库遵循“职责分离（Separation of Concerns）”的原则，按生命周期和功能模块进行扁平化分类：

```
ops-toolbox/ (当前仓库)
├── docs/       # 📚 【全局文档中心】存放详细的架构说明、离线部署 SOP 和使用手册
│   ├── nginx_install_manual.md
│   └── redis_install_manual.md
│
├── install/    # ⚙️ 【核心安装器】完全幂等、支持离线/在线双模式的中间件部署脚本
│   ├── nginx_install.sh
│   └── redis_install.sh
│
├── setup/      # 🛠️ 【环境初始化】系统级别的基线配置与初始化调优工具
│   ├── set_linux_sources.sh   # 自动测速并替换最优 Linux 软件源
│   └── wsl_proxy_setup.sh     # WSL 环境宿主机代理一键配置
│
├── docker/     # 🐳 【容器化资产】统一管理镜像构建与容器编排引擎
│   ├── base-image/            # 基础镜像构建文件 (如 Debian-base Dockerfile)
│   └── wrappers/              # 针对各个服务的标准启动封装脚本 (Start scripts)
│       ├── start_nginx.sh
│       └── start_redis.sh
│
└── python/     # 🐍 【高级语言工具】处理 Shell 难以胜任的复杂文本或自动化逻辑
    └── md_to_docx.py          # Markdown 转换工具等
```

## 🚀 快速开始

### 1. 克隆仓库

将本仓库克隆到您的 Linux 或 WSL 服务器上（建议放置在具有规范管理权限的目录下，例如 `~/scripts/` 或 `/opt/ops-tools/`）：

```
git clone https://github.com/itihub/scripts.git ~/scripts
cd ~/scripts
```

### 2. 典型使用场景示例

**场景 A：配置全新的一台服务器环境**

```
# 进入环境初始化目录，一键替换国内最优源
cd setup
bash set_linux_sources.sh
```

**场景 B：在生产环境内网安装 Redis**

```
# 查阅说明文档以了解离线包制作和部署细节
cat docs/redis_install_manual.md

# 执行企业级一键部署
cd install
bash redis_install.sh
```

**场景 C：利用封装脚本快速拉起测试容器**

```
# 使用标准化的入口指令启动服务
cd docker/wrappers
bash start_mariadb.sh
```

## 🤝 贡献与维护

- **新增组件：** 任何新增的安装脚本请放入 `install/` 目录，并在 `docs/` 下同步提供 `<软件名>_install_manual.md` 说明。
- **脚本规范：** 所有的 Shell 脚本要求带有 `h` 或 `-help` 参数，并在执行关键步骤（如编译、覆盖系统文件）前具备幂等性状态检测 (`SKIP_COMPILE`)。