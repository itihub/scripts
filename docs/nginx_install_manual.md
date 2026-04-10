# Nginx 自动化编译安装脚本 (nginx_install.sh) 使用手册

本手册详细介绍了 `nginx_install.sh` 的功能、配置项以及在不同环境（在线、离线、预编译分发）下的具体使用方法。

## 一、 脚本核心特性

- **完全幂等性**：支持重复执行。如果检测到目标版本已安装，会自动跳过耗时的下载和编译阶段（`SKIP_COMPILE` 机制），仅修复权限和系统服务配置。
- **环境自适应**：自动探测宿主机是否支持 `Systemd`，支持降级使用原生二进制命令管理进程。
- **多模式运行**：内置标准安装、仅下载、便携打包三种模式。
- **安全加固**：默认创建专职无登录权限的 `nginx` 用户运行进程，防止 Root 越权。

## 二、 全局配置说明

在执行脚本前，您可以使用文本编辑器（如 `vim scripts/install/nginx_install.sh`）修改脚本开头的配置区：

```
# ================= 配置区 =================
NGINX_VER="1.28.3"           # Nginx 目标版本
PCRE_VER="10.42"             # 核心正则依赖库版本
OPENSSL_VER="3.3.0"          # SSL 依赖库版本
ZLIB_VER="1.3.1"             # 压缩依赖库版本

INSTALL_DIR="/app/nginx/install" # 最终程序的安装路径
SRC_DIR="/app/nginx/src"         # 源码下载、解压与编译的临时工作目录

SKIP_SERVICE_SETUP="false"       # 设为 true 则不注册 Systemd 开机自启服务
RUN_USER="nginx"                 # Nginx Worker 进程的运行用户
RUN_GROUP="nginx"                # Nginx Worker 进程的运行组
# ==========================================
```

## 三、 使用模式详解

通过命令行参数，您可以控制脚本执行不同的流程。您可以通过执行 `bash nginx_install.sh -h` 来随时查看帮助信息。

### 1. 标准部署模式 (在线环境 / 已有离线包)

**命令**：

```
bash nginx_install.sh
```

**行为说明**：

- 检查 GCC/Make 编译环境。
- 自动下载缺少的源码包到 `SRC_DIR`（如果离线环境已提前放置好压缩包，则自动跳过下载）。
- 编译并安装 Nginx。
- 配置运行用户、权限及 Systemd 守护进程。
- 启动 Nginx 服务。

### 2. 仅下载模式 (外网桥接机)

**命令**：

```
bash nginx_install.sh -d
# 或
bash nginx_install.sh --download-only
```

**行为说明**：
专为**筹备离线资源**设计。脚本会直接下载 `NGINX_VER`、`PCRE_VER` 等所有配置的依赖压缩包到 `SRC_DIR` 目录，下载完成后**立即退出**，不进行任何解压和编译操作。

### 3. 便携打包模式 (制作绿色离线包)

**命令**：

```
bash nginx_install.sh -p
# 或
bash nginx_install.sh --portable
```

**行为说明**：
外网预编译的核心模式。脚本完成下载和全量编译，并在生成最终的可执行程序后，将其直接打包为 `nginx_portable_架构_版本号.tar.gz` 格式的绿色便携包（如 `nginx_portable_x86_64_1.28.3.tar.gz`）。打包完成后退出，**不会**去注册 Systemd 服务，也不会污染当前机器的配置。

## 四、 核心机制剖析：SKIP_COMPILE (跳过编译)

在离线物理机部署时，您可能会疑惑：“为什么内网机没有 GCC 环境，直接执行这个脚本也能成功装上？”

答案在于脚本内置的 `SKIP_COMPILE` 探测逻辑：

1. 脚本每次运行首步，会检查 `INSTALL_DIR/sbin/nginx` 是否存在。
2. 如果存在，且版本号与 `NGINX_VER` 匹配，脚本会将内置变量 `SKIP_COMPILE` 设为 `true`。
3. 当 `SKIP_COMPILE=true` 时，脚本将**直接跳过 [1/7] 到 [4/7] 步**（跳过编译环境验证、下载、解压、`make install`）。
4. 脚本直接从 **[5/7] 配置运行用户与权限** 开始接管。

**最佳实践场景**：配合“便携打包模式”生成的压缩包，您在内网解压后再次运行此脚本，它就会利用 `SKIP_COMPILE` 机制，秒级完成系统服务注册与进程启动，完美实现无编译器的离线一键部署！

## 五、 典型实战流程：完全离线部署

以下是利用本脚本在**断网内网机**上部署 Nginx 的标准 SOP（标准作业程序）：

**Step 1: 在外网桥接机操作**

```
# 制作便携式绿色离线包
bash nginx_install.sh -p

# 执行后，会在 SRC_DIR 目录生成类似 nginx_portable_x86_64_1.28.3.tar.gz 的压缩包。
# 将该压缩包以及 nginx_install.sh 脚本一并拷贝至 U 盘或跳板机。
```

**Step 2: 在内网离线机操作**

```
# 1. 假设您的配置 INSTALL_DIR 为 /app/nginx/install，请先创建其父目录
mkdir -p /app/nginx

# 2. 将离线包解压至父目录（解压后会自动形成 /app/nginx/install 结构）
tar -zxvf nginx_portable_x86_64_1.28.3.tar.gz -C /app/nginx

# 3. 赋予脚本执行权限并运行
chmod +x nginx_install.sh
bash nginx_install.sh

# 此时屏幕会提示："检测到 Nginx 已成功安装... 跳过源码编译步骤！"
# 脚本自动完成用户创建和 Systemd 服务启动。部署完成！
```