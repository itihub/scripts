# Shell 脚本调试与验证指南

在将自动化运维脚本（如 `install_redis.sh`）推向生产环境之前，严格的逻辑验证是必不可少的。本指南总结了 4 种轻量、标准、安全的脚本调试与测试方法。

## 1. 语法预检模式 (Dry-Run)

**适用场景**：写完脚本后的第一道防线，用于排查低级的拼写错误、括号未闭合、`if/fi` 缺失等语法错误。

该命令**不会真正执行**脚本内的任何逻辑，仅做静态语法扫描：

```
bash -n scripts/install/redis_install.sh
```

*(💡 提示：如果执行后没有任何输出，说明基础语法完全正确。)*

## 2. 执行追踪模式 (Debug Mode)

**适用场景**：逻辑验证，用于观察脚本在执行时走进了哪个 `if-else` 分支，以及变量最终被替换成了什么真实的值。

该命令会在屏幕上详细打印脚本执行的每一步（前面带 `+` 号）：

```
bash -x scripts/install/redis_install.sh --download-only
```

*(💡 提示：重点观察含有变量的行，确认路径或密码变量是否按预期传递。)*

## 3. Docker 沙箱验证 (Sandbox) - 最推荐

**适用场景**：全流程真实模拟。包含创建用户、修改系统配置、编译 C 语言源码等“破坏性/污染性”操作时，绝不能在宿主机直接跑。

**推荐镜像**：`debian:bookworm-slim` (约 30MB，标准 GNU 环境，无底层差异导致的编译误报)。

```
# 1. 启动并进入一个阅后即焚（--rm）的干净沙箱，挂载当前代码库
docker run -it --rm -v $(pwd):/workspace debian:bookworm-slim bash

# 2. 在沙箱内容器执行（模拟内网干净的一张白纸）
cd /workspace
apt-get update && apt-get install -y wget procps # 补充基础工具
bash scripts/install/redis_install.sh
```

## 4. 打桩/占位法 (Echo Mocking)

**适用场景**：快速测试控制流，但不想真地去跑耗时的 `make` 编译，也不想执行危险的 `rm -rf`。

**操作方法**：直接修改脚本，将高危或耗时命令前加上 `echo` 屏蔽执行。
例如，临时将脚本中的编译和删除部分改成这样：

```
echo "would run: rm -rf redis-${REDIS_VER}"
# make -j $(nproc) && make install
echo "mock: make install completed"
```

执行后，您可以快速阅览整个安装流程的日志打印是否顺畅，从而确认参数解析与流程跳转正确无误。