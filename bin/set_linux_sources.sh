#!/bin/bash

# --- 颜色定义 ---
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}--- Linux 软件源设置脚本 ---${NC}"

# --- 1. 识别操作系统类型和版本信息 ---
OS_TYPE=""
OS_CODENAME="" # Debian/Ubuntu
OS_VERSION=""   # Red Hat/Fedora
OS_ID=""        # 如 ubuntu, centos, fedora

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID=$ID
    case "$ID" in
        ubuntu|debian|linuxmint|deepin)
            OS_TYPE="debian"
            OS_CODENAME=$VERSION_CODENAME
            if [ -z "$OS_CODENAME" ]; then # Fallback for older Debian or some derivatives
                OS_CODENAME=$(lsb_release -cs 2>/dev/null)
            fi
            ;;
        centos|rhel|fedora|almalinux|rocky)
            OS_TYPE="redhat"
            OS_VERSION=$VERSION_ID
            ;;
        *)
            echo -e "${RED}不支持的操作系统类型：${ID}。本脚本目前仅支持 Debian/Ubuntu 系和 Red Hat/CentOS/Fedora 系。${NC}"
            echo "脚本退出。"
            exit 1
            ;;
    esac
elif [ -f /etc/redhat-release ]; then # Fallback for older Red Hat systems
    OS_TYPE="redhat"
    OS_VERSION=$(grep -oP 'release \K[\d.]+' /etc/redhat-release | cut -d'.' -f1)
elif type lsb_release >/dev/null 2>&1; then # Fallback for Debian-like systems
    OS_ID=$(lsb_release -i -s)
    if [[ "$OS_ID" == "Ubuntu" || "$OS_ID" == "Debian" || "$OS_ID" == "LinuxMint" || "$OS_ID" == "Deepin" ]]; then
        OS_TYPE="debian"
        OS_CODENAME=$(lsb_release -cs)
    else
        echo -e "${RED}无法识别的操作系统类型。本脚本目前仅支持 Debian/Ubuntu 系和 Red Hat/CentOS/Fedora 系。${NC}"
        echo "脚本退出。"
        exit 1
    fi
else
    echo -e "${RED}无法确定操作系统类型和版本。请手动检查您的系统。${NC}"
    echo "脚本退出。"
    exit 1
fi

echo -e "${YELLOW}检测到操作系统类型：${OS_ID} (归属：${OS_TYPE} 系)${NC}"

if [ "$OS_TYPE" == "debian" ]; then
    if [ -z "$OS_CODENAME" ]; then
        echo -e "${RED}错误：无法获取 Debian/Ubuntu 版本代号。请确保您的系统配置正确。${NC}"
        echo "脚本退出。"
        exit 1
    fi
    echo -e "${GREEN}版本代号为：${OS_CODENAME}${NC}"
else # redhat
    if [ -z "$OS_VERSION" ]; then
        echo -e "${RED}错误：无法获取 Red Hat/Fedora 版本号。请确保您的系统配置正确。${NC}"
        echo "脚本退出。"
        exit 1
    fi
    echo -e "${GREEN}版本号为：${OS_VERSION}${NC}"
fi

# --- 2. 备份原有软件源配置文件 ---
echo -e "${YELLOW}正在备份原有软件源配置文件...${NC}"

if [ "$OS_TYPE" == "debian" ]; then
    SOURCES_LIST_FILE="/etc/apt/sources.list"
    BACKUP_FILE="${SOURCES_LIST_FILE}.bak"
    if [ ! -f "$BACKUP_FILE" ]; then
        sudo cp "$SOURCES_LIST_FILE" "$BACKUP_FILE"
        echo -e "${GREEN}已将 ${SOURCES_LIST_FILE} 备份到 ${BACKUP_FILE}${NC}"
    else
        echo -e "${YELLOW}备份文件 ${BACKUP_FILE} 已存在，跳过备份。${NC}"
    fi
elif [ "$OS_TYPE" == "redhat" ]; then
    REPO_DIR="/etc/yum.repos.d"
    BACKUP_DIR="${REPO_DIR}.bak"
    if [ ! -d "$BACKUP_DIR" ]; then
        sudo cp -r "$REPO_DIR" "$BACKUP_DIR"
        echo -e "${GREEN}已将 ${REPO_DIR} 备份到 ${BACKUP_DIR}${NC}"
    else
        echo -e "${YELLOW}备份目录 ${BACKUP_DIR} 已存在，跳过备份。${NC}"
    fi
fi

# --- 3. 让用户选择镜像源 ---
echo -e "\n${YELLOW}请选择您想使用的软件镜像源：${NC}"
if [ "$OS_TYPE" == "debian" ]; then
    echo -e "  ${GREEN}[1]${NC} 清华大学开源软件镜像站 (Ubuntu/Debian) ${YELLOW}(默认)${NC}"
    echo -e "  ${GREEN}[2]${NC} 阿里云开源镜像站 (Ubuntu/Debian)"
    echo -e "  ${GREEN}[3]${NC} 华为云开源镜像站 (Ubuntu/Debian)"
    echo -e "  ${GREEN}[4]${NC} 中国科学技术大学开源软件镜像 (Ubuntu/Debian)"
    echo -e "  ${GREEN}[5]${NC} 网易开源镜像站 (Ubuntu/Debian)"
elif [ "$OS_TYPE" == "redhat" ]; then
    echo -e "  ${GREEN}[1]${NC} 清华大学开源软件镜像站 (CentOS/Fedora) ${YELLOW}(默认)${NC}"
    echo -e "  ${GREEN}[2]${NC} 阿里云开源镜像站 (CentOS/Fedora)"
    echo -e "  ${GREEN}[3]${NC} 华为云开源镜像站 (CentOS/Fedora)"
    echo -e "  ${GREEN}[4]${NC} 中国科学技术大学开源软件镜像 (CentOS/Fedora)"
    # Note: 163.com generally doesn't provide specific CentOS/Fedora mirrors like it does for Ubuntu.
    # So we don't list option 5 for Red Hat type.
fi

read -p "请输入数字选择 (默认 1): " CHOICE

MIRROR_BASE_URL=""
case "$CHOICE" in
    1|"") # 默认或选择1
        if [ "$OS_TYPE" == "debian" ]; then
            MIRROR_BASE_URL="https://mirrors.tuna.tsinghua.edu.cn"
        else
            MIRROR_BASE_URL="https://mirrors.tuna.tsinghua.edu.cn"
        fi
        echo -e "${GREEN}您选择了：清华大学开源软件镜像站${NC}"
        ;;
    2)
        if [ "$OS_TYPE" == "debian" ]; then
            MIRROR_BASE_URL="https://mirrors.aliyun.com"
        else
            MIRROR_BASE_URL="https://mirrors.aliyun.com"
        fi
        echo -e "${GREEN}您选择了：阿里云开源镜像站${NC}"
        ;;
    3)
        if [ "$OS_TYPE" == "debian" ]; then
            MIRROR_BASE_URL="https://repo.huaweicloud.com"
        else
            MIRROR_BASE_URL="https://repo.huaweicloud.com"
        fi
        echo -e "${GREEN}您选择了：华为云开源镜像站${NC}"
        ;;
    4)
        if [ "$OS_TYPE" == "debian" ]; then
            MIRROR_BASE_URL="https://mirrors.ustc.edu.cn"
        else
            MIRROR_BASE_URL="https://mirrors.ustc.edu.cn"
        fi
        echo -e "${GREEN}您选择了：中国科学技术大学开源软件镜像${NC}"
        ;;
    5)
        if [ "$OS_TYPE" == "debian" ]; then # 163 only for debian-like
            MIRROR_BASE_URL="https://mirrors.163.com"
            echo -e "${GREEN}您选择了：网易开源镜像站${NC}"
        else
            MIRROR_BASE_URL="https://mirrors.tuna.tsinghua.edu.cn" # Fallback to default for Red Hat if 5 is chosen
            echo -e "${YELLOW}无效的选择，默认使用：清华大学开源软件镜像站${NC}"
        fi
        ;;
    *)
        if [ "$OS_TYPE" == "debian" ]; then
            MIRROR_BASE_URL="https://mirrors.tuna.tsinghua.edu.cn" # Default for debian-like
        else
            MIRROR_BASE_URL="https://mirrors.tuna.tsinghua.edu.cn" # Default for redhat-like
        fi
        echo -e "${YELLOW}无效的选择，默认使用：清华大学开源软件镜像站${NC}"
        ;;
esac

# --- 4. 生成新的软件源配置 ---
echo -e "${YELLOW}正在生成新的软件源配置文件...${NC}"

if [ "$OS_TYPE" == "debian" ]; then
    sudo bash -c "cat <<EOF > ${SOURCES_LIST_FILE}
# 由脚本自动生成，原文件已备份至 ${BACKUP_FILE}
deb ${MIRROR_BASE_URL}/ubuntu/ ${OS_CODENAME} main restricted universe multiverse
deb-src ${MIRROR_BASE_URL}/ubuntu/ ${OS_CODENAME} main restricted universe multiverse

deb ${MIRROR_BASE_URL}/ubuntu/ ${OS_CODENAME}-security main restricted universe multiverse
deb-src ${MIRROR_BASE_URL}/ubuntu/ ${OS_CODENAME}-security main restricted universe multiverse

deb ${MIRROR_BASE_URL}/ubuntu/ ${OS_CODENAME}-updates main restricted universe multiverse
deb-src ${MIRROR_BASE_URL}/ubuntu/ ${OS_CODENAME}-updates main restricted universe multiverse

# Optional: Uncomment if you need backports or proposed repositories
# deb ${MIRROR_BASE_URL}/ubuntu/ ${OS_CODENAME}-backports main restricted universe multiverse
# deb-src ${MIRROR_BASE_URL}/ubuntu/ ${OS_CODENAME}-backports main restricted universe multiverse

# deb ${MIRROR_BASE_URL}/ubuntu/ ${OS_CODENAME}-proposed main restricted universe multiverse
# deb-src ${MIRROR_BASE_URL}/ubuntu/ ${OS_CODENAME}-proposed main restricted universe multiverse
EOF"
    echo -e "${GREEN}Debian/Ubuntu 软件源已成功设置为 ${MIRROR_BASE_URL}/ubuntu/${NC}"

elif [ "$OS_TYPE" == "redhat" ]; then
    # Create a new repo file, disabling default repos first
    sudo rm -f ${REPO_DIR}/*.repo # Remove all existing .repo files
    sudo bash -c "cat <<EOF > ${REPO_DIR}/${OS_ID}-repo.repo
# 由脚本自动生成，原仓库文件已备份至 ${BACKUP_DIR}
[baseos]
name=${OS_ID} - BaseOS
baseurl=${MIRROR_BASE_URL}/centos/${OS_VERSION}/BaseOS/\$arch/os/
gpgcheck=1
enabled=1
gpgkey=${MIRROR_BASE_URL}/centos/RPM-GPG-KEY-CentOS-Official

[appstream]
name=${OS_ID} - AppStream
baseurl=${MIRROR_BASE_URL}/centos/${OS_VERSION}/AppStream/\$arch/os/
gpgcheck=1
enabled=1
gpgkey=${MIRROR_BASE_URL}/centos/RPM-GPG-KEY-CentOS-Official

[extras]
name=${OS_ID} - Extras
baseurl=${MIRROR_BASE_URL}/centos/${OS_VERSION}/extras/\$arch/os/
gpgcheck=1
enabled=1
gpgkey=${MIRROR_BASE_URL}/centos/RPM-GPG-KEY-CentOS-Official

# For Fedora, use different paths
# [fedora-base]
# name=Fedora \$releasever - Base
# baseurl=${MIRROR_BASE_URL}/fedora/releases/\$releasever/Everything/\$basearch/os/
# enabled=1
# gpgcheck=1
# gpgkey=${MIRROR_BASE_URL}/fedora/RPM-GPG-KEY-fedora-\$releasever-\$basearch

# [fedora-updates]
# name=Fedora \$releasever - Updates
# baseurl=${MIRROR_BASE_URL}/fedora/updates/\$releasever/Everything/\$basearch/os/
# enabled=1
# gpgcheck=1
# gpgkey=${MIRROR_BASE_URL}/fedora/RPM-GPG-KEY-fedora-\$releasever-\$basearch
EOF"
    echo -e "${GREEN}Red Hat/CentOS/Fedora 软件源已成功设置为 ${MIRROR_BASE_URL}/${OS_ID}/${NC}"
fi


# --- 5. 更新软件包列表 ---
echo -e "\n${YELLOW}正在更新软件包列表...${NC}"
if [ "$OS_TYPE" == "debian" ]; then
    if sudo apt update; then
        echo -e "${GREEN}软件包列表更新成功！${NC}"
    else
        echo -e "${RED}警告：软件包列表更新失败。请检查您的网络连接或镜像源配置。${NC}"
    fi
elif [ "$OS_TYPE" == "redhat" ]; then
    if sudo dnf makecache; then # Fedora/newer CentOS
        echo -e "${GREEN}DNF 缓存更新成功！${NC}"
    elif sudo yum makecache; then # Older CentOS
        echo -e "${GREEN}YUM 缓存更新成功！${NC}"
    else
        echo -e "${RED}警告：软件包缓存更新失败。请检查您的网络连接或镜像源配置。${NC}"
    fi
fi

# --- 6. 建议升级已安装的软件包 ---
echo -e "\n${YELLOW}建议您运行相应的命令来升级已安装的软件包：${NC}"
if [ "$OS_TYPE" == "debian" ]; then
    echo -e "  ${GREEN}sudo apt upgrade -y${NC}"
elif [ "$OS_TYPE" == "redhat" ]; then
    echo -e "  ${GREEN}sudo dnf upgrade -y${NC} (或 ${GREEN}sudo yum upgrade -y${NC} 对于旧版CentOS)"
fi

echo -e "\n${GREEN}脚本执行完毕。${NC}"
