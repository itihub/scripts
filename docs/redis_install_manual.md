# Redis 自动化编译安装脚本 (redis_install.sh) 使用手册

本手册详细介绍了 `redis_install.sh` 的功能、配置项以及在不同环境（在线、离线、预编译分发）下的具体使用方法。

## 一、 脚本核心特性

- **完全幂等性**：支持重复执行。如果检测到目标版本已安装，会自动跳过耗时的下载和编译阶段（`SKIP_COMPILE` 机制），仅修复权限和系统服务配置。
- **环境自适应**：自动探测宿主机是否支持 `Systemd`，支持降级使用原生二进制命令和带密码认证的 `redis-cli` 管理进程。
- **多模式运行**：内置标准安装、仅下载、便携打包三种模式。
- **安全与规范加固**：默认创建专职无登录权限的 `redis` 用户运行进程；自动修改配置文件，强制实现**程序与数据（RDB/AOF持久化文件、Logs日志）分离**，并支持一键设置访问密码和自定义端口。

## 二、 全局配置说明

在执行脚本前，您可以使用文本编辑器修改脚本开头的配置区：

```
# ================= 配置区 =================
REDIS_VER="7.2.4"                # Redis 目标版本

INSTALL_DIR="/app/redis/install" # 程序最终安装路径
SRC_DIR="/app/redis/src"         # 源码下载、解压与编译的临时工作目录
CONF_DIR="${INSTALL_DIR}/conf"   # 配置文件目录
DATA_DIR="/app/redis/data"       # 数据与日志独立存储目录（实现程序与数据分离）

# 网络与安全配置
REDIS_PORT="6379"                # Redis 监听端口
REDIS_PASS=""                    # 访问密码（设置为空 "" 则不开启密码验证）

# 服务控制配置
SKIP_SERVICE_SETUP="true"        # 设为 true 则不注册 Systemd 开机自启服务
RUN_USER="redis"                 # Redis 进程的运行用户
RUN_GROUP="redis"                # Redis 进程的运行组
# ==========================================
```

## 三、 使用模式详解

通过命令行参数，您可以控制脚本执行不同的流程。您可以通过执行 `bash redis_install.sh -h` 来随时查看帮助信息。

### 1. 标准部署模式 (在线环境 / 已有离线包)

**命令**：

```
bash redis_install.sh
```

**行为说明**：

- 检查 GCC/Make 编译环境。
- 自动下载缺少的源码包到 `SRC_DIR`（如果离线环境已提前放置好压缩包，则自动跳过下载）。
- 编译并安装 Redis。
- 自动生成 `redis.conf`，并注入端口、密码、后台运行及日志/数据路径配置。
- 配置运行用户、权限及 Systemd 守护进程。
- 启动 Redis 服务。

### 2. 仅下载模式 (外网桥接机)

**命令**：

```
bash redis_install.sh -d
# 或
bash redis_install.sh --download-only
```

**行为说明**：
专为**筹备离线资源**设计。脚本会直接下载 `REDIS_VER` 配置的版本压缩包到 `SRC_DIR` 目录，下载完成后**立即退出**，不进行任何解压和编译操作。

### 3. 便携打包模式 (制作绿色离线包)

**命令**：

```
bash redis_install.sh -p
# 或
bash redis_install.sh --portable
```

**行为说明**：
外网预编译的核心模式。脚本完成下载、全量编译和配置修改后，直接将已编译好的程序主目录打包为 `redis_portable_架构_版本号.tar.gz` 格式的绿色便携包（如 `redis_portable_x86_64_7.2.4.tar.gz`）。打包完成后退出，**不会**去注册 Systemd 服务，也不会污染当前机器的用户配置。

## 四、 核心机制剖析：SKIP_COMPILE (跳过编译)

在离线物理机部署时，利用预编译包结合本脚本可以实现“秒级接管”。

触发 `SKIP_COMPILE` 的探测逻辑如下：

1. 脚本每次运行首步，会检查 `${INSTALL_DIR}/bin/redis-server` 是否存在。
2. 如果存在，且通过 `v` 提取的版本号与 `REDIS_VER` 匹配，脚本会将内置变量 `SKIP_COMPILE` 设为 `true`。
3. 当 `SKIP_COMPILE=true` 时，脚本将**直接跳过 [1/7] 到 [4/7] 步**（跳过编译环境验证、下载、解压、`make install` 及初始配置生成）。
4. 脚本直接从 **[5/7] 配置运行用户与权限** 开始接管。

**最佳实践场景**：配合“便携打包模式”生成的压缩包，您在内网解压后再次运行此脚本，它不仅能秒级启动进程，还会自动为您补齐 `${DATA_DIR}/data` 等必需的数据存储目录，并赋予正确的读写权限！

## 五、 典型实战流程：完全离线部署

以下是利用本脚本在**断网内网机**上部署 Redis 的标准 SOP（标准作业程序）：

**Step 1: 在外网桥接机操作**

```
# 制作便携式绿色离线包
bash redis_install.sh -p

# 执行后，会在 SRC_DIR 目录生成类似 redis_portable_x86_64_7.2.4.tar.gz 的压缩包。
# 将该压缩包以及 redis_install.sh 脚本一并拷贝至 U 盘或内网跳板机。
```

**Step 2: 在内网离线机操作**

```
# 1. 假设您的配置 INSTALL_DIR 为 /app/redis/install，请先创建其父目录
mkdir -p /app/redis

# 2. 将离线包解压至父目录（解压后会自动形成 /app/redis/install 结构）
tar -zxvf redis_portable_x86_64_7.2.4.tar.gz -C /app/redis

# 3. 赋予脚本执行权限并运行
chmod +x redis_install.sh
bash redis_install.sh

# 此时屏幕会提示："检测到 Redis 已成功安装... 跳过源码编译步骤！"
# 脚本将自动完成用户创建、数据目录建立和进程安全启动。部署完成！
```