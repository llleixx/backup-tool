#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

readonly REPO="llleixx/backup-tool"
readonly RESTIC_REPO="restic/restic"

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
readonly RESTIC_INSTALL_PATH="/usr/local/bin/restic"
readonly MANAGED_MANIFEST_PATH="${ROOT_DIR}/.managed-manifest"

PKG_MANAGER=""

detect_pkg_manager() {
    if command -v apt-get &>/dev/null; then
        PKG_MANAGER="apt"
        msg_info "检测到包管理器: apt"
        apt-get update -y
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
        msg_info "检测到包管理器: dnf"
        msg_info "正在确保 EPEL 仓库已启用..."
        dnf install -y epel-release
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
        msg_warn "未检测到支持的包管理器"
        exit 1
    fi
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        msg_err "错误：此脚本必须以 root 权限运行"
        exit 1
    fi
}

check_systemd() {
    if ! command -v systemctl &>/dev/null; then
        msg_err "错误：此脚本需要 systemd，但在您的系统中未找到 systemctl 命令"
        msg_err "请在支持 systemd 的 Linux 发行版上运行此脚本"
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
            msg_err "错误：不支持的包管理器"
            msg_err "请手动安装依赖项 '$dep_pkg'"
            exit 1
            ;;
    esac

    # 4. 验证安装是否成功
    if command -v "$dep_cmd" &>/dev/null; then
        msg_info "依赖项 '$dep_pkg' 安装成功"
    else
        msg_err "错误：尝试通过 '$PKG_MANAGER' 安装 '$dep_pkg' 后，仍然找不到 '$dep_cmd' 命令"
        exit 1
    fi
}

normalize_version() {
    printf '%s' "${1#v}"
}

version_lt() {
    local left right
    left=$(normalize_version "$1")
    right=$(normalize_version "$2")
    [[ "$left" != "$right" && "$(printf '%s\n' "$left" "$right" | sort -V | head -n1)" == "$left" ]]
}

get_github_latest_release_json() {
    local repo="$1"
    curl -fsSL \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/${repo}/releases/latest"
}

get_restic_linux_arch() {
    case "$(uname -m)" in
        x86_64|amd64) echo "amd64" ;;
        i386|i486|i586|i686) echo "386" ;;
        aarch64|arm64) echo "arm64" ;;
        armv5*|armv6*|armv7*|armv8l|armhf) echo "arm" ;;
        ppc64le) echo "ppc64le" ;;
        riscv64) echo "riscv64" ;;
        s390x) echo "s390x" ;;
        mips64el|mips64le) echo "mips64le" ;;
        mips64) echo "mips64" ;;
        mipsel|mipsle) echo "mipsle" ;;
        mips) echo "mips" ;;
        *)
            msg_err "错误：暂不支持的 Linux 架构: $(uname -m)"
            exit 1
            ;;
    esac
}

get_restic_release_asset_url() {
    local release_json="$1"
    local arch="$2"
    local latest_version asset_name
    latest_version=$(normalize_version "$(jq -er '.tag_name' <<< "$release_json")")
    asset_name="restic_${latest_version}_linux_${arch}.bz2"

    jq -er --arg asset_name "$asset_name" \
        '.assets[] | select(.name == $asset_name) | .browser_download_url' \
        <<< "$release_json" | head -n1
}

install_restic_from_github() {
    if [[ "$(uname -s)" != "Linux" ]]; then
        msg_err "错误：restic GitHub 安装流程仅支持 Linux"
        exit 1
    fi

    local current_path=""
    local current_version=""
    local release_json latest_tag latest_version arch asset_url
    local tmp_archive tmp_binary

    if command -v restic &>/dev/null; then
        current_path=$(command -v restic)
        current_version=$(restic version | head -n1 | awk '{print $2}')
    fi

    release_json=$(get_github_latest_release_json "$RESTIC_REPO")
    latest_tag=$(jq -er '.tag_name' <<< "$release_json")
    latest_version=$(normalize_version "$latest_tag")
    arch=$(get_restic_linux_arch)
    asset_url=$(get_restic_release_asset_url "$release_json" "$arch")

    if [[ -n "$current_version" && "$current_path" == "$RESTIC_INSTALL_PATH" ]] && ! version_lt "$current_version" "$latest_version"; then
        msg_ok "restic 已是最新版本 (${current_version#v})，安装位置: $RESTIC_INSTALL_PATH"
        return 0
    fi

    if [[ -n "$current_version" ]]; then
        msg_info "检测到现有 restic: ${current_path} (${current_version#v})"
    fi

    msg_info "正在从 GitHub Release 安装 restic ${latest_version} (${arch})..."
    tmp_archive=$(mktemp -t "restic_${latest_version}_${arch}_XXXXXX.bz2")
    tmp_binary=$(mktemp -t "restic_bin_XXXXXX")

    curl -fsSL -o "$tmp_archive" "$asset_url"
    bzip2 -dc "$tmp_archive" > "$tmp_binary"
    install -m 0755 "$tmp_binary" "$RESTIC_INSTALL_PATH"
    rm -f "$tmp_archive" "$tmp_binary"

    if ! "$RESTIC_INSTALL_PATH" version &>/dev/null; then
        msg_err "错误：restic 安装完成后验证失败"
        exit 1
    fi

    if [[ -n "$current_version" ]]; then
        msg_ok "restic 已更新为 ${latest_version}，安装位置: $RESTIC_INSTALL_PATH"
    else
        msg_ok "restic 已安装为 ${latest_version}，安装位置: $RESTIC_INSTALL_PATH"
    fi
}

get_repo_latest_version() {
    local repo="$1"
    get_github_latest_release_json "$repo" | jq -er '.tag_name'
}

get_repo_latest_source_code() {
    local repo="$1"
    local target="$2"
    local latest_version
    latest_version=$(get_repo_latest_version "$repo")
    target="${target:-./${repo##*/}-${latest_version}.tar.gz}"
    curl -fsSL -o "$target" "https://github.com/${repo}/archive/refs/tags/${latest_version}.tar.gz"
}

cleanup_legacy_managed_paths() {
    rm -rf \
        "${ROOT_DIR}/.github" \
        "${ROOT_DIR}/lib"
    rm -f \
        "${ROOT_DIR}/.gitignore" \
        "${ROOT_DIR}/LICENSE" \
        "${ROOT_DIR}/README.md" \
        "${ROOT_DIR}/backup-tool.sh" \
        "${ROOT_DIR}/install.sh"
}

cleanup_previous_managed_paths() {
    local rel_path

    if [[ ! -f "$MANAGED_MANIFEST_PATH" ]]; then
        cleanup_legacy_managed_paths
        return 0
    fi

    while IFS= read -r rel_path || [[ -n "$rel_path" ]]; do
        [[ -n "$rel_path" ]] || continue
        case "$rel_path" in
            conf|conf/*|hooks|hooks/*|backup_list.txt)
                continue
                ;;
        esac
        rm -rf "${ROOT_DIR}/${rel_path}"
    done < "$MANAGED_MANIFEST_PATH"
}

write_managed_manifest() {
    local source_dir="$1"
    local tmp_manifest

    tmp_manifest=$(mktemp -p "$ROOT_DIR" ".managed-manifest.tmp.XXXXXX")
    (
        cd "$source_dir"
        find . -mindepth 1 -printf '%P\n' | LC_ALL=C sort
    ) > "$tmp_manifest"
    mv "$tmp_manifest" "$MANAGED_MANIFEST_PATH"
}

install_project_files() {
    local archive_path="$1"
    local extract_dir

    extract_dir="$(mktemp -d -t backup-tool-src-XXXXXX)"
    tar -xzf "$archive_path" -C "$extract_dir" --strip-components=1

    cleanup_previous_managed_paths
    cp -a "$extract_dir"/. "$ROOT_DIR"/
    write_managed_manifest "$extract_dir"
    rm -rf "$extract_dir"
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
    msg_ok "'service-failure-notify@.service' 已创建"

    cat > "$success_service_path" << EOF
[Unit]
Description=Notify user of service success for %i

[Service]
Type=oneshot
User=root
ExecStart=${SCRIPT_DIR}/service-success-notify.sh %i
EOF
    msg_ok "'service-success-notify@.service' 已创建"
    systemctl daemon-reload
}

main() {
    local source_archive
    source_archive=$(mktemp -t backup-tool-latest-XXXXXX.tar.gz)
    trap '[[ -n "${source_archive-}" ]] && rm -f "${source_archive}"' EXIT

    check_root
    check_systemd
    ensure_dependency curl
    ensure_dependency jq
    ensure_dependency bzip2
    install_restic_from_github
    ensure_dependency msmtp

    msg_info "正在创建工作目录..."
    mkdir -p "$ROOT_DIR" "$CONF_DIR" "$SCRIPT_DIR"

    msg_info "正在从 GitHub 获取最新版本的源码..."
    get_repo_latest_source_code "$REPO" "$source_archive"

    msg_info "正在安装源码到 ${ROOT_DIR}..."
    install_project_files "$source_archive"
    rm -f "$source_archive"
    chmod +x "${ROOT_DIR}"/*.sh "${SCRIPT_DIR}"/*.sh

    msg_info "正在设置 systemd 通知服务..."
    setup_notification_services

    msg_info "正在创建符号链接到 /usr/local/bin/ ..."
    ln -sf ${ROOT_DIR}/backup-tool.sh /usr/local/bin/but
    ln -sf ${ROOT_DIR}/backup-tool.sh /usr/local/bin/backup-tool

    msg_ok "\n安装完成！"
    msg_info "现在可以运行 'backup-tool' 或者 'but' 来开始配置备份任务"
    sleep 2

    exec bash -l -c "${ROOT_DIR}/backup-tool.sh"
}

main "$@"
