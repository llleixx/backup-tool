#!/usr/bin/env bash
set -e
set -o pipefail

readonly REPO="lllei/backup-tool"

readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_NC='\033[0m' # No Color

msg() { echo -e "$@"; }
msg_ok() { msg "${COLOR_GREEN}$*${COLOR_NC}"; }
msg_err() { msg "${COLOR_RED}$*${COLOR_NC}" >&2; }
msg_warn() { msg "${COLOR_YELLOW}$*${COLOR_NC}"; }
msg_info() { msg "${COLOR_BLUE}$*${COLOR_NC}"; }

readonly ROOT_DIR="/opt/backup"
readonly CONF_DIR="$ROOT_DIR/conf"
readonly SCRIPT_DIR="$ROOT_DIR/lib"
readonly SYSTEMD_DIR="/etc/systemd/system"
readonly MIN_RESTIC_VERSION="0.17.0"

PKG_MANAGER=""

detect_pkg_manager() {
    if command -v apt-get &>/dev/null; then
        PKG_MANAGER="apt"
        msg_info "检测到包管理器: apt"
        apt-get update -y
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
        msg_info "检测到包管理器: dnf"
    elif command -v yum &>/dev/null; then
        PKG_MANAGER="yum"
        msg_info "检测到包管理器: yum"
    elif command -v pacman &>/dev/null; then
        PKG_MANAGER="pacman"
        msg_info "检测到包管理器: pacman"
    elif command -v zypper &>/dev/null; then
        PKG_MANAGER="zypper"
        msg_info "检测到包管理器: zypper"
    elif command -v apk &>/dev/null; then
        PKG_MANAGER="apk"
        msg_info "检测到包管理器: apk"
    else
        PKG_MANAGER="unsupported"
        msg_warn "未检测到支持的包管理器。"
        exit 1
    fi
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        msg_err "错误：此脚本必须以 root 权限运行。"
        exit 1
    fi
}

check_systemd() {
    if ! command -v systemctl &>/dev/null; then
        msg_err "错误：此脚本需要 systemd，但在您的系统中未找到 systemctl 命令。"
        msg_err "请在支持 systemd 的 Linux 发行版上运行此脚本。"
        exit 1
    fi
}

ensure_dependency() {
    local dep_cmd="$1"
    local dep_pkg="${2:-$dep_cmd}"
    
    if command -v "$dep_cmd" &>/dev/null; then
        return 0
    fi

    # 1. 如果命令不存在，则尝试安装
    msg_warn "依赖项 '$dep_cmd' 未找到，尝试自动安装..."

    # 2. 如果包管理器尚未确定，则执行一次检测
    if [[ -z "$PKG_MANAGER" ]]; then
        detect_pkg_manager
    fi

    # 3. 使用已检测到的包管理器进行安装
    case "$PKG_MANAGER" in
        "apt")
            apt-get install -y "$dep_pkg"
            ;;
        "dnf")
            dnf install -y "$dep_pkg"
            ;;
        "yum")
            yum install -y "$dep_pkg"
            ;;
        "pacman")
            pacman -Syu --noconfirm "$dep_pkg"
            ;;
        "zypper")
            zypper install -y "$dep_pkg"
            ;;
        "apk")
            apk add "$dep_pkg"
            ;;
        *)
            msg_error "错误：不支持的包管理器。"
            msg_error "请手动安装依赖项 '$dep_pkg'。"
            exit 1
            ;;
    esac

    # 4. 验证安装是否成功
    if command -v "$dep_cmd" &>/dev/null; then
        msg_info "依赖项 '$dep_pkg' 安装成功！"
    else
        msg_error "错误：尝试通过 '$PKG_MANAGER' 安装 '$dep_pkg' 后，仍然找不到 '$dep_cmd' 命令。"
        exit 1
    fi
}

ensure_restic_version() {
    local current_version
    current_version=$(restic version | head -n1 | cut -d' ' -f2)
    if [[ "$(printf '%s\n' "$MIN_RESTIC_VERSION" "$current_version" | sort -V | head -n1)" != "$MIN_RESTIC_VERSION" ]]; then
        msg_warn "警告：您的 restic 版本 ($current_version) 过低，此脚本要求 restic >= $MIN_RESTIC_VERSION，开始自动更新。"
        if ! restic self-update; then
            msg_err "错误：restic 更新失败，请使用 restic self-update 手动更新。"
            exit 1
        fi
        msg_ok "restic 已成功更新至最新版本。"
    fi
}

get_repo_latest_version() {
    local repo="$1"
    # 使用 jq 替代 grep/sed，解析更稳定
    curl -s "https://api.github.com/repos/${repo}/releases/latest" | jq -r .tag_name
}

get_repo_latest_source_code() {
    local repo="$1"
    local target="$2"
    latest_version=$(get_repo_latest_version "$repo")
    target="${target:-./${repo##*/}-${latest_version}.tar.gz}"
    curl -L -o "$target" "https://github.com/${repo}/archive/refs/tags/${latest_version}.tar.gz"
}

setup_notification_services() {
    local failure_service_path="${SYSTEMD_DIR}/service-failure-notify@.service"
    local success_service_path="${SYSTEMD_DIR}/service-success-notify@.service"

    cat > "$failure_service_path" << EOF
[Unit]
Description=Notify user of service failure for %i

[Service]
Type=oneshot
User=root
ExecStart=${SCRIPT_DIR}/service-failure-notify.sh %i
EOF
    msg_ok "'service-failure-notify@.service' 已创建。"

    cat > "$success_service_path" << EOF
[Unit]
Description=Notify user of service success for %i

[Service]
Type=oneshot
User=root
ExecStart=${SCRIPT_DIR}/service-success-notify.sh %i
EOF
    msg_ok "'service-success-notify@.service' 已创建。"
    systemctl daemon-reload
}

main() {
    # 添加 trap，确保脚本退出时自动清理临时文件
    trap 'rm -f /tmp/backup-tool-latest.tar.gz' EXIT

    check_root
    check_systemd
    ensure_dependency restic
    ensure_restic_version
    ensure_dependency curl
    ensure_dependency msmtp
    ensure_dependency jq

    msg_info "正在创建工作目录..."
    mkdir -p "$ROOT_DIR" "$CONF_DIR" "$SCRIPT_DIR"

    msg_info "正在从 GitHub 获取最新版本的源码..."
    get_repo_latest_source_code "$REPO" "/tmp/backup-tool-latest.tar.gz"

    msg_info "正在解压源码到 ${ROOT_DIR}..."
    tar -xzf /tmp/backup-tool-latest.tar.gz -C "$ROOT_DIR" --strip-components=1
    chmod +x ${ROOT_DIR}/*.sh ${SCRIPT_DIR}/*.sh

    msg_info "正在设置 systemd 通知服务..."
    setup_notification_services

    msg_info "正在创建符号链接到 /usr/local/bin/ ..."
    ln -sf ${ROOT_DIR}/backup-tool.sh /usr/local/bin/but
    ln -sf ${ROOT_DIR}/backup-tool.sh /usr/local/bin/backup-tool

    msg_ok "\n安装完成！"
    msg_info "现在可以运行 'but.sh' 来开始配置备份任务。"
    sleep 1
    
    ${ROOT_DIR}/backup-tool.sh
}

main "$@"