#!/usr/bin/env bash
#
# 通知处理函数库

add_notify_config() {
    clear
    msg_info "--- 添加新的通知配置 ---"
    local notify_type
    while true; do
        read -rp "请选择通知类型 [1: Telegram, 2: Email]: " choice
        case "$choice" in
            1) notify_type="telegram"; break ;;
            2) notify_type="email"; break ;;
            *) msg_warn "无效的选择。" ;;
        esac
    done
    local conf_id
    conf_id="notify-$(generate_id)"
    local conf_file="${CONF_DIR}/${conf_id}.conf"
    local notify_on_success notify_on_failure
    read -rp "是否在成功时通知? [Y/n]: " choice
    [[ "${choice,,}" == "n" ]] && notify_on_success="false" || notify_on_success="true"
    read -rp "是否在失败时通知? [Y/n]: " choice
    [[ "${choice,,}" == "n" ]] && notify_on_failure="false" || notify_on_failure="true"
    if [[ "$notify_type" == "telegram" ]]; then
        local token chat_id
        read -rp "请输入 Telegram Bot Token: " token
        read -rp "请输入 Telegram Chat ID: " chat_id
        cat > "$conf_file" << EOF
NOTIFY_TYPE="telegram"
NOTIFY_ON_SUCCESS="$notify_on_success"
NOTIFY_ON_FAILURE="$notify_on_failure"
TELEGRAM_BOT_TOKEN="$token"
TELEGRAM_CHAT_ID="$chat_id"
EOF
    elif [[ "$notify_type" == "email" ]]; then
        local smtp_host smtp_port smtp_user smtp_pass from_addr to_addr smtp_tls
        read -rp "请输入 SMTP 服务器地址: " smtp_host
        read -rp "请输入 SMTP 服务器端口: " smtp_port
        read -rp "请输入 SMTP 用户: " smtp_user
        read -rsp "请输入 SMTP 密码/App Password: " smtp_pass; echo
        read -rp "请输入发件人地址 (与 SMTP 用户相同即可): " from_addr
        read -rp "请输入收件人地址: " to_addr
        while true; do
            read -rp "请选择 TLS 类型 [1: starttls, 2: on(SMTPS), 3: off]: " choice
            case "$choice" in
                1) smtp_tls="starttls"; break ;;
                2) smtp_tls="on"; break ;;
                3) smtp_tls="off"; break ;;
                *) msg_warn "无效的选择。" ;;
            esac
        done
        cat > "$conf_file" << EOF
NOTIFY_TYPE="email"
NOTIFY_ON_SUCCESS="$notify_on_success"
NOTIFY_ON_FAILURE="$notify_on_failure"
SMTP_HOST="$smtp_host"
SMTP_PORT="$smtp_port"
SMTP_USER="$smtp_user"
SMTP_PASS="$smtp_pass"
FROM_ADDR="$from_addr"
TO_ADDR="$to_addr"
SMTP_TLS="$smtp_tls"
EOF
    fi
    msg_ok "\n通知配置 '${conf_id}' 已成功创建。"
    pause
}

_view_single_notify_config() {
    local config_id="$1"
    local conf_file="${CONF_DIR}/${config_id}.conf"
    if [[ ! -f "$conf_file" ]]; then msg_err "错误: 找不到配置文件 $conf_file"; return; fi
    msg_info "--- 通知配置详情 [ID: ${config_id}] ---"
    (
        # shellcheck source=/dev/null
        source "$conf_file"
        msg "  通知类型:           $(msg_ok "$NOTIFY_TYPE")"
        msg "  成功时通知:         $(msg_ok "$NOTIFY_ON_SUCCESS")"
        msg "  失败时通知:         $(msg_ok "$NOTIFY_ON_FAILURE")"
        if [[ "$NOTIFY_TYPE" == "telegram" ]]; then
            msg "  Bot Token:          $(msg_warn "[已隐藏]")"
            msg "  Chat ID:            $(msg_ok "$TELEGRAM_CHAT_ID")"
        elif [[ "$NOTIFY_TYPE" == "email" ]]; then
            msg "  SMTP Host:          $(msg_ok "$SMTP_HOST")"
            msg "  SMTP Port:          $(msg_ok "$SMTP_PORT")"
            msg "  SMTP User:          $(msg_ok "$SMTP_USER")"
            msg "  SMTP Pass:          $(msg_warn "[已隐藏]")"
            msg "  发件人:             $(msg_ok "$FROM_ADDR")"
            msg "  收件人:             $(msg_ok "$TO_ADDR")"
            msg "  TLS:                $(msg_ok "$SMTP_TLS")"
        fi
    )
}

view_single_notify_config() {
    clear
    _view_single_notify_config "$1"
}
view_all_notify_configs() {
    clear
    msg_info "--- 所有通知配置 ---"
    for config_id in "$@"; do
        _view_single_notify_config "$config_id"
        echo
    done
}
change_single_notify_config() {
    local config_id="$1"
    local conf_file="${CONF_DIR}/${config_id}.conf"
    if [[ ! -f "$conf_file" ]]; then msg_err "错误: 找不到配置文件 $conf_file"; return 1; fi
    clear
    msg_info "--- 更改通知配置 [ID: ${config_id}] ---"
    # shellcheck source=/dev/null
    source "$conf_file"
    local choice
    msg "\n1. 触发条件"
    read -rp "   是否在成功时通知? 按下 Enter 保留[当前: ${NOTIFY_ON_SUCCESS}] [y/n]: " choice
    if [[ -n "$choice" ]]; then
        [[ "${choice,,}" == "n" ]] && NOTIFY_ON_SUCCESS="false" || NOTIFY_ON_SUCCESS="true"
    fi
    read -rp "   是否在失败时通知? 按下 Enter 保留[当前: ${NOTIFY_ON_FAILURE}] [y/n]: " choice
    if [[ -n "$choice" ]]; then
        [[ "${choice,,}" == "n" ]] && NOTIFY_ON_FAILURE="false" || NOTIFY_ON_FAILURE="true"
    fi
    if [[ "$NOTIFY_TYPE" == "telegram" ]]; then
        msg "\n2. Telegram 设置"
        read -rp "   输入新 Bot Token 或按 Enter 保留: " new_val
        TELEGRAM_BOT_TOKEN=${new_val:-$TELEGRAM_BOT_TOKEN}
        read -rp "   输入新 Chat ID 或按 Enter 保留 [当前: $TELEGRAM_CHAT_ID]: " new_val
        TELEGRAM_CHAT_ID=${new_val:-$TELEGRAM_CHAT_ID}
        cat > "$conf_file" << EOF
NOTIFY_TYPE="telegram"
NOTIFY_ON_SUCCESS="$NOTIFY_ON_SUCCESS"
NOTIFY_ON_FAILURE="$NOTIFY_ON_FAILURE"
TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN"
TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID"
EOF
    elif [[ "$NOTIFY_TYPE" == "email" ]]; then
        msg "\n2. Email 设置"
        read -rp "   输入新 SMTP Host 或按 Enter 保留 [当前: $SMTP_HOST]: " new_val; SMTP_HOST=${new_val:-$SMTP_HOST}
        read -rp "   输入新 SMTP Port 或按 Enter 保留 [当前: $SMTP_PORT]: " new_val; SMTP_PORT=${new_val:-$SMTP_PORT}
        read -rp "   输入新 SMTP User 或按 Enter 保留 [当前: $SMTP_USER]: " new_val; SMTP_USER=${new_val:-$SMTP_USER}
        read -rsp "   输入新 SMTP 密码或按 Enter 保留: " new_val; echo; SMTP_PASS=${new_val:-$SMTP_PASS}
        read -rp "   输入新发件人或按 Enter 保留 [当前: $FROM_ADDR]: " new_val; FROM_ADDR=${new_val:-$FROM_ADDR}
        read -rp "   输入新收件人或按 Enter 保留 [当前: $TO_ADDR]: " new_val; TO_ADDR=${new_val:-$TO_ADDR}
        read -rp "   输入新 TLS 类型 (starttls/on/off) 或按 Enter 保留 [当前: $SMTP_TLS]: " new_val; SMTP_TLS=${new_val:-$SMTP_TLS}
        cat > "$conf_file" << EOF
NOTIFY_TYPE="email"
NOTIFY_ON_SUCCESS="$NOTIFY_ON_SUCCESS"
NOTIFY_ON_FAILURE="$NOTIFY_ON_FAILURE"
SMTP_HOST="$SMTP_HOST"
SMTP_PORT="$SMTP_PORT"
SMTP_USER="$SMTP_USER"
SMTP_PASS="$SMTP_PASS"
FROM_ADDR="$FROM_ADDR"
TO_ADDR="$TO_ADDR"
SMTP_TLS="$SMTP_TLS"
EOF
    fi
    msg_ok "\n配置 ${config_id} 已更新。"
}
delete_single_notify_config() {
    local config_id="$1"
    local need_confirm="${2:-true}"
    local conf_file="${CONF_DIR}/${config_id}.conf"
    if [[ ! -f "$conf_file" ]]; then msg_err "错误: 找不到配置文件 $conf_file"; return; fi
    local notify_type
    notify_type=$(get_value_from_conf "$conf_file" "NOTIFY_TYPE")
    msg_warn "\n--- 删除通知配置 [ID: ${config_id}] ---"
    msg "您将要删除这个 ${notify_type} 通知配置。"
    if [[ "$need_confirm" != "false" ]]; then
        local confirm
        read -rp "您确定要永久删除此配置吗？此操作无法撤销！[y/N]: " confirm
        if [[ "${confirm,,}" != "y" ]]; then
            msg_warn "删除操作已取消。"
            return
        fi
    fi
    rm -f "$conf_file"
    msg_ok "通知配置 ${config_id} 已成功删除。"
}

delete_all_notify_configs() {
    msg_warn "警告：您将删除所有通知配置。此操作无法撤销！"
    local confirm
    read -rp "您确定要继续吗？[y/N]: " confirm
    if [[ "${confirm,,}" != "y" ]]; then
        msg_warn "删除操作已取消。"
        return
    fi
    for config_id in "$@"; do
        delete_single_notify_config "$config_id" "false"
    done
    msg_ok "所有通知配置已成功删除。"
}

test_single_notify_config() {
    conf_file="${CONF_DIR}/$1.conf"
    process_notify "$conf_file" "测试通知" "这是一条测试通知。\n\n如果您收到此消息，说明通知配置工作正常。"
}