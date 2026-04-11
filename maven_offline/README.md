# Maven 仓库离线增量同步方案 (Windows + Linux)

> **适用场景**：企业内网离线开发环境、Maven 项目依赖全量迁移后的日常增量更新。
**核心目标**：首次全量同步与后续日常增量均**共用一套自动化脚本**。彻底告别重复传输几个 G 的全量仓库包，实现一键化的高效搬运。
>

## 一、方案总览

本方案基于 Maven 本地仓库的目录结构特性，通过配套的自动化脚本（精确到秒的时间戳筛选）实现依赖同步。
脚本会自动对比上一次打包的时间（无时间戳则默认提取近期变动），仅提取期间发生变动的依赖文件，打包为轻量级的 ZIP 压缩包，无缝适配 Windows 和 Linux 平台。

**核心工作流**：

1. **外网（联网环境）**：修改 `pom.xml` → 拉取新依赖 → **运行一键打包脚本** → 产出增量/全量 ZIP 包
2. **内网（离线环境）**：导入 ZIP 包 → 强制解压覆盖至本地 Maven 仓库 → 离线环境刷新与验证生效

## 二、目录结构规范

为了保证自动化脚本（基于相对路径推导）正常运行，请务必在你的工作机上保持以下严格的目录结构：

```
maven_offline/              # 你的工作根目录 (名称可自定义)
  ├── repository/           # 【必须手动准备】完整的 Maven 仓库目录 (内外网需保持一致)
  ├── scripts/              # 【必须手动准备】脚本存放区，将打包脚本放入此文件夹
  │     ├── build_incremental.ps1  # Windows 一键打包脚本
  │     └── build_incremental.sh   # Linux 一键打包脚本
  ├── incremental/          # 【脚本自动生成】暂存区：运行脚本时自动生成，存放散装依赖文件
  ├── dist/                 # 【脚本自动生成】分发区：存放最终生成的 ZIP 压缩包
  └── .last_build_time      # 【脚本自动生成】系统隐藏文件，记录上一次成功打包的时间戳
```

## 三、操作步骤

### 阶段一：首次全量同步（仅需执行一次）

首次配置时，通过“全新下载 + 增量脚本”的组合技，即可自动实现全量依赖的提取与打包：

### 1. 外网设置新仓库并拉取全量依赖

首先，修改外网 Maven 的 `settings.xml`，将其本地仓库指向我们的工作目录：

```
<localRepository>D:/maven_offline/repository</localRepository>
```

然后在包含 `pom.xml` 的项目根目录执行，确保项目所需的所有依赖全部下载至该目录：

```
mvn clean package -Dmaven.test.skip=true
```

### 2. 外网执行打包（共用增量脚本）

由于这是首次下载，所有文件的时间戳都是最新的（当天）。此时直接运行 `scripts` 目录下的打包脚本：

- **Windows**: 右键 `build_incremental.ps1` -> **使用 PowerShell 运行**。
- **Linux**: 执行 `./scripts/build_incremental.sh`。

*(注：由于没有历史时间戳标记，脚本会默认提取最近 1 天内的所有文件，从而自动完成了本次的全量依赖打包！)*

### 3. 内网设置本地仓库目录

将外网生成的 `update_xxx.zip` 传输到内网，并解压至内网的 `maven_offline/repository/` 目录下。

接着，修改内网 Maven 的核心配置文件 `settings.xml`，显式指定离线仓库的绝对路径，并开启离线模式：

```
<!-- 在 settings 标签内添加或修改 localRepository 节点 -->
<localRepository>D:/maven_offline/repository</localRepository>

<!-- 强烈建议：配置内网离线模式，防止 Maven 尝试去连接外网下载导致卡顿 -->
<offline>true</offline>
```

*在 IDEA 中：进入 `File` -> `Settings` -> `Build Tools` -> `Maven`，勾选 `Work offline` 并确认 `Local repository` 指向了该目录。*

### 4. 内网拉取后验证

在内网项目根目录执行以下命令，加上 `-o` (offline) 参数强制 Maven 只从本地仓库读取依赖，验证全量迁移是否成功：

```
# 强制离线编译，如果不报错则说明全量依赖已准备就绪
mvn clean compile -o
```

### 阶段二：日常增量同步（高频核心操作）

> **⚠️ 前提操作**：每次在**外网**修改项目依赖后，必须先执行 `mvn clean package -Dmaven.test.skip=true` 让新依赖落盘。
>

### 步骤 1：外网一键生成增量包

直接进入 `scripts` 目录，运行打包脚本：

**🖥️ Windows 平台**：

1. 右键点击 `build_incremental.ps1`，选择 **“使用 PowerShell 运行”**。

**🐧 Linux 平台**：

1. 运行脚本：`./scripts/build_incremental.sh`

**🤖 脚本智能特性说明**：

- 脚本会自动读取 `.last_build_time` 时间戳，精确捕获上次打包之后哪怕只有 1 秒钟的变动。
- **空包防呆**：如果没有检测到任何依赖变化，脚本会直接提示并退出，不会生成多余的空压缩包。

### 步骤 2：内网解压覆盖与离线验证

1. 脚本执行成功后，会在外网的 `update_package/` 目录下生成类似 `update_20240520_143000.zip` 的压缩包。
2. 将此 ZIP 包拷贝到内网对应的目录下。
3. **强制覆盖解压**：
    - **Windows**：右键解压，目标选择内网的 `repository` 目录，遇到提示选 **“全部替换/覆盖”**。
    - **Linux**：在内网终端执行以下命令（注意 `o` 参数代表强制覆盖）：

        ```
        unzip -o update_20240520_143000.zip -d /你的内网路径/maven_offline/repository/
        ```

4. **离线验证生效**：
   在内网终端执行离线编译命令进行最终验证：

    ```
    mvn clean compile -o
    ```

   若出现 `BUILD SUCCESS` 且没有 `Could not resolve dependencies` 的报错，说明增量包已完美融合，更新成功！


## 四、常见问题排查 (FAQ)

| 异常现象 / 报错信息 | 可能原因 | 解决建议 |
| --- | --- | --- |
| **"找不到 Maven 仓库源目录"** | 脚本与 `repository` 目录的相对层级错误。 | 确保脚本**必须**存放在 `scripts/` 子目录下，并且 `repository` 与 `scripts` 是同级目录。 |
| **Linux 提示 "未安装 zip 命令"** | 缺少必要的系统组件。 | CentOS 执行 `sudo yum install zip`；Ubuntu 执行 `sudo apt-get install zip`。 |
| **Windows 运行报语法错误或乱码** | PowerShell 读取 UTF-8 文件时的编码兼容问题。 | 用记事本打开 `.ps1` 文件，选择“另存为”，编码格式选择 **“带有 BOM 的 UTF-8”** 然后覆盖保存。 |
| **内网验证时提示 Cannot resolve XXX** | 打包前没有将依赖同步到外网本地硬盘，或内网覆盖路径错误。 | 1. 确认外网是否先执行了 `mvn clean package` 使得 jar 包落盘。

2. 检查内网解压时是否覆盖进了正确的本地仓库目录。 |
   | **脚本提示“没有发现新增依赖”退出了** | 距上次打包期间确实无变动，或本地 Maven 未更新。 | 这是正常的防呆机制。若确认修改了依赖，请先执行外网构建拉取新包后再运行脚本。 |