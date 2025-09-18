#!/usr/bin/env bash

# --- 消息函数 ---
msg() { echo -e "$@"; }
msg_ok() { msg "${COLOR_GREEN}$*${COLOR_NC}"; }
msg_err() { msg "${COLOR_RED}$*${COLOR_NC}" >&2; }
msg_warn() { msg "${COLOR_YELLOW}$*${COLOR_NC}"; }
msg_info() { msg "${COLOR_BLUE}$*${COLOR_NC}"; }

# --- 辅助函数 ---
check_root() {
    if [[ $EUID -ne 0 ]]; then
        msg_err "错误：此脚本必须以 root 权限运行。"
        exit 1
    fi
}

check_dependency() {
    local dep_name="$1"
    if ! command -v "$dep_name" &>/dev/null; then
        msg_err "错误：依赖项 '$dep_name' 命令未找到。请先安装它。"
        exit 1
    fi
}

check_restic_version() {
    local current_version
    current_version=$(restic version | head -n1 | cut -d' ' -f2)
    if [[ "$(printf '%s\n' "$MIN_RESTIC_VERSION" "$current_version" | sort -V | head -n1)" != "$MIN_RESTIC_VERSION" ]]; then
        msg_err "错误：您的 restic 版本 ($current_version) 过低。此脚本要求 restic >= $MIN_RESTIC_VERSION。"
        msg_err "你可以使用 restic self-update 命令来更新 restic。"
        exit 1
    fi
}

install_rclone() {
    if command -v rclone &>/dev/null; then
        msg_ok "rclone 已安装，跳过安装步骤。"
        return 0
    fi

    msg_info "rclone 未安装，开始安装..."
    local install_script_url="https://rclone.org/install.sh"
    if curl -fsSL "$install_script_url" | bash; then
        msg_ok "rclone 安装成功！"
    else
        msg_err "错误：rclone 安装失败，请手动安装 rclone。"
        exit 1
    fi
}

self_update() {
    local latest_version
    latest_version=$(get_repo_latest_version "$REPO")
    if [[ "$latest_version" != "$VERSION" ]]; then
        msg_info "检测到新版本 $latest_version，当前版本 $VERSION，开始更新..."
        local tmp_file="/tmp/backup-tool-update-${latest_version}.tar.gz"
        local tmp_dir
        tmp_dir="$(mktemp -d -t backup-tool-update-XXXXXX)"
        get_repo_latest_source_code "$REPO" "$tmp_file"
        if tar -xzf "$tmp_file" -C "$tmp_dir" --strip-components=1; then
            cp -r "$tmp_dir/"* "${ROOT_DIR}/"
            rm -rf "$tmp_dir" "$tmp_file"
            msg_ok "更新成功！请重新运行脚本以使用最新版本。"
            exit 0
        else
            msg_err "错误：解压更新包失败，请手动更新。"
            exit 1
        fi
    else
        msg_ok "当前已是最新版本 ($VERSION)。"
    fi
}

is_valid_oncalendar() {
    systemd-analyze calendar "$1" &>/dev/null
}

pause() {
    echo
    read -rp "按 $(msg_ok Enter) 继续..."
}

generate_id() {
    head /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 8
}

get_value_from_conf() {
    local file="$1"
    local key="$2"
    grep -E "^${key}=" "$file" | sed -E "s/^${key}=[\"']?([^\"']*)[\"']?/\1/"
}

unset_config_vars() {
    unset CONFIG_ID BACKUP_FILES_LIST RESTIC_REPOSITORY RESTIC_PASSWORD CRON_SCHEDULE KEEP_DAILY KEEP_WEEKLY
}