#!/usr/bin/env bash
#
# 工具函数库

if [[ -n "${BACKUP_TOOL_UTILS_SH_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
readonly BACKUP_TOOL_UTILS_SH_LOADED=1

# --- 消息函数 ---
msg() { echo -e "$@"; }
msg_ok() { msg "${COLOR_GREEN-}$*${COLOR_NC-}"; }
msg_err() { msg "${COLOR_RED-}$*${COLOR_NC-}" >&2; }
msg_warn() { msg "${COLOR_YELLOW-}$*${COLOR_NC-}"; }
msg_info() { msg "${COLOR_BLUE-}$*${COLOR_NC-}"; }

readonly CONFIG_FILE_PERMS="600"
readonly CONFIG_DIR_PERMS="700"

# --- 常用函数 --- 
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
        msg_err "请直接重新运行 install.sh，脚本会通过 GitHub Release 安装或更新 /usr/local/bin/restic。"
        msg_err "如果当前 shell 仍指向旧的 restic 路径，请重新登录，或执行 'hash -r' 后再试。"
        exit 1
    fi
}

get_repo_latest_version() {
    local repo="$1"
    curl -fsSL \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/${repo}/releases/latest" | jq -er '.tag_name'
}

get_repo_latest_source_code() {
    local repo="$1"
    local target="$2"
    local latest_version
    latest_version=$(get_repo_latest_version "$repo")
    target="${target:-./${repo##*/}-${latest_version}.tar.gz}"
    curl -fsSL -o "$target" "https://github.com/${repo}/archive/refs/tags/${latest_version}.tar.gz"
}

install_rclone() {
    if command -v rclone &>/dev/null; then
        msg_ok "rclone 已安装，跳过安装步骤。"
        pause
        return 0
    fi

    msg_info "rclone 未安装，开始安装..."
    local install_script_url="https://rclone.org/install.sh"
    local install_script
    install_script=$(mktemp -t rclone-install-XXXXXX.sh)

    if curl -fsSL -o "$install_script" "$install_script_url" && bash "$install_script"; then
        mkdir -p ~/.config/rclone
        touch ~/.config/rclone/rclone.conf
        rm -f "$install_script"
        msg_ok "rclone 安装成功！"
        msg_info "rclone 配置文件位于 ~/.config/rclone/rclone.conf"
        msg_info "如果没有配置文件，可以使用 'rclone config' 命令创建。"
        pause
    else
        rm -f "$install_script"
        msg_err "错误：rclone 安装失败，请手动安装 rclone。"
        return 1
    fi

    return 0
}

self_update() {
    local latest_version
    local tmp_install_script

    if ! latest_version=$(get_repo_latest_version "$REPO"); then
        msg_err "错误：获取最新版本信息失败，请稍后重试。"
        return 1
    fi

    if [[ "$latest_version" == "$VERSION" ]]; then
        msg_ok "当前已是最新版本 ($VERSION)。"
        pause
        return 0
    fi

    msg_info "检测到新版本 $latest_version，当前版本 $VERSION，开始执行完整升级..."
    tmp_install_script=$(mktemp -t backup-tool-install-XXXXXX.sh)

    if ! curl -fsSL -o "$tmp_install_script" "https://raw.githubusercontent.com/${REPO}/main/install.sh"; then
        rm -f "$tmp_install_script"
        msg_err "错误：下载最新安装脚本失败，请稍后重试。"
        return 1
    fi

    chmod +x "$tmp_install_script"
    msg_info "正在调用最新安装脚本完成升级..."
    exec 3<"$tmp_install_script"
    rm -f "$tmp_install_script"
    exec bash /dev/fd/3
}

_uninstall_script() {
    local config_id

    mapfile -t backup_configs_ids < <(find "${CONF_DIR}" -maxdepth 1 -name 'backup-*.conf' -print0 | xargs -0 -r -n1 basename | sed 's/\.conf$//')
    for config_id in "${backup_configs_ids[@]}"; do
        _delete_single_backup_config "$config_id" false || true
    done

    mapfile -t notify_configs_ids < <(find "${CONF_DIR}" -maxdepth 1 -name 'notify-*.conf' -print0 | xargs -0 -r -n1 basename | sed 's/\.conf$//')
    for config_id in "${notify_configs_ids[@]}"; do
        delete_single_notify_config "$config_id" false || true
    done

    rm -rf "${ROOT_DIR}"
    rm -f /etc/systemd/system/service-failure-notify@.service
    rm -f /etc/systemd/system/service-success-notify@.service
    rm -f /usr/local/bin/backup-tool
    rm -f /usr/local/bin/but
    systemctl daemon-reload
    systemctl reset-failed
}

uninstall_script() {
    msg_warn "警告：确定要卸载脚本吗？"
    local confirm
    prompt_for_yes_no "您确定要继续吗？" confirm "n"
    if [[ "$confirm" == "true" ]]; then
        _uninstall_script
        msg_ok "脚本已成功卸载。"
        exit 0
    else
        msg_info "卸载操作已取消。"
        pause
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

ensure_config_storage_permissions() {
    mkdir -p "${CONF_DIR}"
    chmod "${CONFIG_DIR_PERMS}" "${CONF_DIR}"
    find "${CONF_DIR}" -maxdepth 1 -type f -name '*.conf' -exec chmod "${CONFIG_FILE_PERMS}" {} + 2>/dev/null || true
}

config_is_json() {
    local file="$1"
    jq -e 'type == "object"' "$file" &>/dev/null
}

config_kind_from_path() {
    case "$(basename "$1")" in
        backup-*.conf) echo "backup" ;;
        notify-*.conf) echo "notify" ;;
        *) echo "unknown" ;;
    esac
}

_decode_legacy_config_value() {
    local raw_value="$1"

    if [[ "$raw_value" =~ ^\"(.*)\"$ ]]; then
        raw_value="${BASH_REMATCH[1]}"
        raw_value="${raw_value//\\\\/\\}"
        raw_value="${raw_value//\\\"/\"}"
    elif [[ "$raw_value" =~ ^\'(.*)\'$ ]]; then
        raw_value="${BASH_REMATCH[1]}"
    fi

    printf '%s' "$raw_value"
}

config_get_legacy_value() {
    local file="$1"
    local key="$2"
    local line parsed_key raw_value

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            parsed_key="${BASH_REMATCH[1]}"
            raw_value="${BASH_REMATCH[2]}"
            if [[ "$parsed_key" == "$key" ]]; then
                _decode_legacy_config_value "$raw_value"
                return 0
            fi
        fi
    done < "$file"

    return 1
}

config_has_key() {
    local file="$1"
    local key="$2"

    if [[ ! -f "$file" ]]; then
        return 1
    fi

    if config_is_json "$file"; then
        jq -e --arg key "$key" 'has($key)' "$file" &>/dev/null
    else
        config_get_legacy_value "$file" "$key" >/dev/null
    fi
}

config_get_optional() {
    local file="$1"
    local key="$2"
    local default_value="${3:-}"

    if [[ ! -f "$file" ]]; then
        printf '%s' "$default_value"
        return 1
    fi

    if config_is_json "$file"; then
        jq -r \
            --arg key "$key" \
            --arg default "$default_value" \
            'if has($key) then .[$key] else $default end
             | if . == null then "" elif type == "string" then . else tostring end' \
            "$file"
        return 0
    fi

    if config_get_legacy_value "$file" "$key"; then
        return 0
    fi

    printf '%s' "$default_value"
    return 0
}

config_get_required() {
    local file="$1"
    local key="$2"

    if ! config_has_key "$file" "$key"; then
        msg_err "错误：配置文件 '$file' 缺少必需字段 '$key'"
        return 1
    fi

    config_get_optional "$file" "$key"
}

config_write_json() {
    local file="$1"
    local json_content="$2"
    local file_dir file_name tmp_file

    file_dir=$(dirname "$file")
    file_name=$(basename "$file")
    mkdir -p "$file_dir"
    tmp_file=$(mktemp -p "$file_dir" ".${file_name}.tmp.XXXXXX")

    if ! printf '%s\n' "$json_content" | jq '.' > "$tmp_file"; then
        rm -f "$tmp_file"
        msg_err "错误：无法写入配置文件 '$file'"
        return 1
    fi

    chmod "${CONFIG_FILE_PERMS}" "$tmp_file"
    mv "$tmp_file" "$file"
    return 0
}

build_backup_config_json() {
    jq -n \
        --arg config_id "$1" \
        --arg backup_files_list "$2" \
        --arg repository "$3" \
        --arg password "$4" \
        --arg on_calendar "$5" \
        --arg keep_daily "$6" \
        --arg keep_weekly "$7" \
        --arg group_by "$8" \
        --arg pre_backup_hook "$9" \
        --arg post_success_hook "${10}" \
        --arg post_failure_hook "${11}" \
        '{
            CONFIG_ID: $config_id,
            BACKUP_FILES_LIST: $backup_files_list,
            RESTIC_REPOSITORY: $repository,
            RESTIC_PASSWORD: $password,
            ON_CALENDAR: $on_calendar,
            KEEP_DAILY: $keep_daily,
            KEEP_WEEKLY: $keep_weekly,
            GROUP_BY: $group_by,
            PRE_BACKUP_HOOK: $pre_backup_hook,
            POST_SUCCESS_HOOK: $post_success_hook,
            POST_FAILURE_HOOK: $post_failure_hook
        }'
}

build_notify_config_json() {
    local notify_type="$1"
    local notify_on_success="$2"
    local notify_on_failure="$3"

    case "$notify_type" in
        telegram)
            jq -n \
                --arg notify_type "$notify_type" \
                --arg notify_on_success "$notify_on_success" \
                --arg notify_on_failure "$notify_on_failure" \
                --arg bot_token "$4" \
                --arg chat_id "$5" \
                '{
                    NOTIFY_TYPE: $notify_type,
                    NOTIFY_ON_SUCCESS: $notify_on_success,
                    NOTIFY_ON_FAILURE: $notify_on_failure,
                    TELEGRAM_BOT_TOKEN: $bot_token,
                    TELEGRAM_CHAT_ID: $chat_id
                }'
            ;;
        email)
            jq -n \
                --arg notify_type "$notify_type" \
                --arg notify_on_success "$notify_on_success" \
                --arg notify_on_failure "$notify_on_failure" \
                --arg smtp_host "$4" \
                --arg smtp_port "$5" \
                --arg smtp_user "$6" \
                --arg smtp_pass "$7" \
                --arg from_addr "$8" \
                --arg to_addr "$9" \
                --arg smtp_tls "${10}" \
                '{
                    NOTIFY_TYPE: $notify_type,
                    NOTIFY_ON_SUCCESS: $notify_on_success,
                    NOTIFY_ON_FAILURE: $notify_on_failure,
                    SMTP_HOST: $smtp_host,
                    SMTP_PORT: $smtp_port,
                    SMTP_USER: $smtp_user,
                    SMTP_PASS: $smtp_pass,
                    FROM_ADDR: $from_addr,
                    TO_ADDR: $to_addr,
                    SMTP_TLS: $smtp_tls
                }'
            ;;
        *)
            msg_err "错误：未知的通知类型 '$notify_type'"
            return 1
            ;;
    esac
}

_migrate_backup_config_to_json() {
    local file="$1"
    local config_id backup_files_list repository password on_calendar keep_daily keep_weekly group_by
    local pre_backup_hook post_success_hook post_failure_hook

    config_id=$(config_get_legacy_value "$file" "CONFIG_ID") || { msg_err "错误：旧备份配置缺少 CONFIG_ID: $file"; return 1; }
    backup_files_list=$(config_get_legacy_value "$file" "BACKUP_FILES_LIST") || { msg_err "错误：旧备份配置缺少 BACKUP_FILES_LIST: $file"; return 1; }
    repository=$(config_get_legacy_value "$file" "RESTIC_REPOSITORY") || { msg_err "错误：旧备份配置缺少 RESTIC_REPOSITORY: $file"; return 1; }
    password=$(config_get_optional "$file" "RESTIC_PASSWORD" "")
    on_calendar=$(config_get_legacy_value "$file" "ON_CALENDAR") || { msg_err "错误：旧备份配置缺少 ON_CALENDAR: $file"; return 1; }
    keep_daily=$(config_get_legacy_value "$file" "KEEP_DAILY") || { msg_err "错误：旧备份配置缺少 KEEP_DAILY: $file"; return 1; }
    keep_weekly=$(config_get_legacy_value "$file" "KEEP_WEEKLY") || { msg_err "错误：旧备份配置缺少 KEEP_WEEKLY: $file"; return 1; }
    group_by=$(config_get_optional "$file" "GROUP_BY" "tags")
    pre_backup_hook=$(config_get_optional "$file" "PRE_BACKUP_HOOK" "")
    post_success_hook=$(config_get_optional "$file" "POST_SUCCESS_HOOK" "")
    post_failure_hook=$(config_get_optional "$file" "POST_FAILURE_HOOK" "")

    build_backup_config_json \
        "$config_id" \
        "$backup_files_list" \
        "$repository" \
        "$password" \
        "$on_calendar" \
        "$keep_daily" \
        "$keep_weekly" \
        "$group_by" \
        "$pre_backup_hook" \
        "$post_success_hook" \
        "$post_failure_hook"
}

_migrate_notify_config_to_json() {
    local file="$1"
    local notify_type notify_on_success notify_on_failure

    notify_type=$(config_get_legacy_value "$file" "NOTIFY_TYPE") || { msg_err "错误：旧通知配置缺少 NOTIFY_TYPE: $file"; return 1; }
    notify_on_success=$(config_get_optional "$file" "NOTIFY_ON_SUCCESS" "true")
    notify_on_failure=$(config_get_optional "$file" "NOTIFY_ON_FAILURE" "true")

    case "$notify_type" in
        telegram)
            build_notify_config_json \
                "$notify_type" \
                "$notify_on_success" \
                "$notify_on_failure" \
                "$(config_get_legacy_value "$file" "TELEGRAM_BOT_TOKEN")" \
                "$(config_get_legacy_value "$file" "TELEGRAM_CHAT_ID")"
            ;;
        email)
            build_notify_config_json \
                "$notify_type" \
                "$notify_on_success" \
                "$notify_on_failure" \
                "$(config_get_legacy_value "$file" "SMTP_HOST")" \
                "$(config_get_legacy_value "$file" "SMTP_PORT")" \
                "$(config_get_legacy_value "$file" "SMTP_USER")" \
                "$(config_get_optional "$file" "SMTP_PASS" "")" \
                "$(config_get_legacy_value "$file" "FROM_ADDR")" \
                "$(config_get_legacy_value "$file" "TO_ADDR")" \
                "$(config_get_optional "$file" "SMTP_TLS" "starttls")"
            ;;
        *)
            msg_err "错误：旧通知配置包含未知类型 '$notify_type': $file"
            return 1
            ;;
    esac
}

migrate_config_file_if_needed() {
    local file="$1"
    local kind json_content

    [[ -f "$file" ]] || return 0

    if config_is_json "$file"; then
        chmod "${CONFIG_FILE_PERMS}" "$file"
        return 0
    fi

    kind=$(config_kind_from_path "$file")
    case "$kind" in
        backup)
            json_content=$(_migrate_backup_config_to_json "$file") || return 1
            ;;
        notify)
            json_content=$(_migrate_notify_config_to_json "$file") || return 1
            ;;
        *)
            msg_warn "跳过未知类型配置文件: $file"
            return 0
            ;;
    esac

    config_write_json "$file" "$json_content" || return 1
    msg_info "已将旧配置迁移为 JSON: $file"
    return 0
}

migrate_all_configs_if_needed() {
    local file failed=0

    ensure_config_storage_permissions
    shopt -s nullglob
    for file in "${CONF_DIR}"/backup-*.conf "${CONF_DIR}"/notify-*.conf; do
        migrate_config_file_if_needed "$file" || failed=1
    done
    shopt -u nullglob

    return "$failed"
}

ensure_config_json_file() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        config_write_json "$file" '{}'
        return $?
    fi

    migrate_config_file_if_needed "$file"
}

get_value_from_conf() {
    local file="$1"
    local key="$2"
    config_get_optional "$file" "$key" ""
}

prompt_for_hook_path() {
    local prompt_message="$1"
    local input_variable_name="$2"
    local allow_empty="${3:-true}"
    local current_value="${4:-}"
    local user_input

    while true; do
        if [[ -n "$current_value" ]]; then
            read -rp "${prompt_message} [当前: ${current_value}] (留空保留, 输入 none 清空): " user_input
            if [[ -z "$user_input" ]]; then
                eval "$input_variable_name=\"__KEEP__\""
                return
            fi
            if [[ "${user_input,,}" == "none" ]]; then
                eval "$input_variable_name=\"\""
                return
            fi
        else
            read -rp "${prompt_message} (留空跳过): " user_input
            if [[ -z "$user_input" ]]; then
                if [[ "$allow_empty" == "true" ]]; then
                    eval "$input_variable_name=\"\""
                    return
                fi
                msg_err "错误：输入不能为空，请重新输入。"
                continue
            fi
        fi

        if [[ -f "$user_input" ]]; then
            eval "$input_variable_name=\"\$user_input\""
            return
        fi
        msg_warn "脚本文件不存在: $user_input"
    done
}

unset_config_vars() {
    unset CONFIG_ID BACKUP_FILES_LIST RESTIC_REPOSITORY RESTIC_PASSWORD ON_CALENDAR KEEP_DAILY KEEP_WEEKLY
    unset PRE_BACKUP_HOOK POST_SUCCESS_HOOK POST_FAILURE_HOOK
}

update_config_value() {
    local conf_file="$1"
    local key="$2"
    local new_value="$3"
    local file_dir file_name tmp_file

    ensure_config_json_file "$conf_file" || return 1

    file_dir=$(dirname "$conf_file")
    file_name=$(basename "$conf_file")
    tmp_file=$(mktemp -p "$file_dir" ".${file_name}.tmp.XXXXXX")

    if ! jq --arg key "$key" --arg value "$new_value" '.[$key] = $value' "$conf_file" > "$tmp_file"; then
        rm -f "$tmp_file"
        msg_err "错误：更新配置文件失败: $conf_file"
        return 1
    fi

    chmod "${CONFIG_FILE_PERMS}" "$tmp_file"
    mv "$tmp_file" "$conf_file"
}

update_config_if_change() {
    local conf_file="$1"
    local key="$2"
    local new_value="$3"
    if [[ "$new_value" == "__KEEP__" ]]; then
        return
    fi
    update_config_value "$conf_file" "$key" "$new_value"
}

update_config_if_set() {
    local conf_file="$1"
    local key="$2"
    local new_value="$3"
    if [[ -n "$new_value" ]]; then
        update_config_value "$conf_file" "$key" "$new_value"
    fi
}

# --- 输入函数 ---
prompt_for_input() {
    local prompt_message="$1"
    local input_variable_name="$2"
    local allow_empty="${3:-false}"
    local user_input

    while true; do
        read -rp "$prompt_message: " user_input
        if [[ -n "$user_input" ]]; then
            eval "$input_variable_name=\"\$user_input\""
            break
        elif [[ "$allow_empty" == "true" ]]; then
            eval "$input_variable_name=\"\""
            break
        else
            msg_err "错误：输入不能为空，请重新输入。"
        fi
    done
}

prompt_for_number() {
    local prompt_message="$1"
    local input_variable_name="$2"
    local allow_empty="${3:-false}"
    local user_input

    while true; do
        read -rp "$prompt_message: " user_input
        if [[ -z "$user_input" && "$allow_empty" == "true" ]]; then
            eval "$input_variable_name=\"\""
            break
        elif [[ "$user_input" =~ ^[0-9]+$ ]]; then
            eval "$input_variable_name=\"\$user_input\""
            break
        else
            msg_err "错误：输入无效，请输入一个数字。"
        fi
    done
}

prompt_for_password() {
    local prompt_message="$1"
    local password_var="$2"
    local allow_empty="${3:-false}"
    local password_input password_confirm

    while true; do
        read -rsp "$prompt_message: " password_input
        echo

        if [[ -z "$password_input" && "$allow_empty" == "true" ]]; then
            eval "$password_var=\"\""
            break
        elif [[ -z "$password_input" ]]; then
            msg_err "密码不能为空，请重新输入"
            continue
        fi
        
        read -rsp "确认密码: " password_confirm
        echo

        if [[ "$password_input" == "$password_confirm" ]]; then
            eval "$password_var=\"\$password_input\""
            break
        else
            msg_err "密码不匹配，请重新输入"
        fi
    done
}

prompt_for_yes_no() {
    local prompt_message="$1"
    local result_var="$2"
    local default_value="${3:-n}"
    local choice
    local normalized_default

    case "${default_value,,}" in
        y|yes|true) normalized_default="true" ;;
        n|no|false|"") normalized_default="false" ;;
        *)
            msg_warn "未知的 yes/no 默认值 '$default_value'，将按 'no' 处理。"
            normalized_default="false"
            ;;
    esac

    local prompt_suffix
    if [[ "$normalized_default" == "true" ]]; then
        prompt_suffix="[Y/n]"
    else
        prompt_suffix="[y/N]"
    fi

    while true; do
        read -rp "$prompt_message $prompt_suffix: " choice
        choice=${choice:-$normalized_default}
        case "${choice,,}" in
            y|yes|true)
                eval "$result_var=true"
                break
                ;;
            n|no|false)
                eval "$result_var=false"
                break
                ;;
            *)
                msg_warn "无效的输入，请输入 'y' 或 'n'。"
                ;;
        esac
    done
}
