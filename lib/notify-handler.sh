#!/usr/bin/env bash
#
# 通知处理函数库

add_notify_config() {
    clear
    msg_info "--- 添加通知配置 ---"
    local notify_type choice
    
    # 1. 选择通知类型
    while true; do
        prompt_for_number "通知类型 [1: Telegram, 2: Email]" choice
        case "$choice" in
            1) notify_type="telegram"; break ;;
            2) notify_type="email"; break ;;
            *) msg_warn "无效选择" ;;
        esac
    done
    
    # 2. 生成配置文件
    local conf_id
    conf_id="notify-$(generate_id)"
    local conf_file="${CONF_DIR}/${conf_id}.conf"
    local notify_on_success notify_on_failure
    prompt_for_yes_no "成功时通知?" notify_on_success "y"
    prompt_for_yes_no "失败时通知?" notify_on_failure "y"
    
    # 3. 配置通知参数
    if [[ "$notify_type" == "telegram" ]]; then
        local token chat_id
        prompt_for_input "Telegram Bot Token" token
        prompt_for_input "Telegram Chat ID" chat_id
        cat > "$conf_file" << EOF
NOTIFY_TYPE="telegram"
NOTIFY_ON_SUCCESS="$notify_on_success"
NOTIFY_ON_FAILURE="$notify_on_failure"
TELEGRAM_BOT_TOKEN="$token"
TELEGRAM_CHAT_ID="$chat_id"
EOF
    elif [[ "$notify_type" == "email" ]]; then
        local smtp_host smtp_port smtp_user smtp_pass from_addr to_addr smtp_tls
        prompt_for_input "SMTP 服务器地址" smtp_host
        prompt_for_number "SMTP 服务器端口" smtp_port
        prompt_for_input "SMTP 用户名" smtp_user
        prompt_for_input "SMTP 密码/App Password" smtp_pass
        prompt_for_input "发件人地址" from_addr
        prompt_for_input "收件人地址" to_addr
        while true; do
            prompt_for_number "TLS 类型 [1: starttls, 2: on(SMTPS), 3: off]" choice
            case "$choice" in
                1) smtp_tls="starttls"; break ;;
                2) smtp_tls="on"; break ;;
                3) smtp_tls="off"; break ;;
                *) msg_warn "无效选择" ;;
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
    msg_ok "通知配置 '${conf_id}' 创建成功"
    pause
}

_view_single_notify_config() {
    local config_id="$1"
    local conf_file="${CONF_DIR}/${config_id}.conf"
    if [[ ! -f "$conf_file" ]]; then 
        msg_err "错误: 找不到配置文件 $conf_file"
        return
    fi
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
    if [[ ! -f "$conf_file" ]]; then 
        msg_err "配置文件不存在: $conf_file"
        return 1
    fi
    clear
    msg_info "--- 修改通知配置 [ID: ${config_id}] ---"
    # shellcheck source=/dev/null
    source "$conf_file"
    
    # 1. 触发条件
    local new_on_success new_on_failure
    prompt_for_yes_no "成功时通知 [当前: ${NOTIFY_ON_SUCCESS}] (留空保留)" new_on_success "${NOTIFY_ON_SUCCESS}"
    prompt_for_yes_no "失败时通知 [当前: ${NOTIFY_ON_FAILURE}] (留空保留)" new_on_failure "${NOTIFY_ON_FAILURE}"
    
    # 2. 具体设置
    if [[ "$NOTIFY_TYPE" == "telegram" ]]; then
        local new_bot_token new_chat_id
        prompt_for_input "Bot Token (留空保留)" new_bot_token true
        prompt_for_input "Chat ID [当前: $TELEGRAM_CHAT_ID] (留空保留)" new_chat_id true
    elif [[ "$NOTIFY_TYPE" == "email" ]]; then
        local new_host new_port new_user new_pass new_from new_to new_tls
        prompt_for_input "SMTP Host [当前: $SMTP_HOST] (留空保留)" new_host true
        prompt_for_number "SMTP Port [当前: $SMTP_PORT] (留空保留)" new_port true
        prompt_for_input "SMTP User [当前: $SMTP_USER] (留空保留)" new_user true
        prompt_for_password "SMTP 密码 (留空保留)" new_pass true
        prompt_for_input "发件人 [当前: $FROM_ADDR] (留空保留)" new_from true
        prompt_for_input "收件人 [当前: $TO_ADDR] (留空保留)" new_to true
        prompt_for_input "TLS 类型 [当前: $SMTP_TLS] (留空保留)" new_tls true
    fi

    msg_info "保存配置到 $conf_file"
    if [[ "$new_on_success" != "$NOTIFY_ON_SUCCESS" ]]; then
        update_config_value "$conf_file" "NOTIFY_ON_SUCCESS" "$new_on_success"
    fi
    if [[ "$new_on_failure" != "$NOTIFY_ON_FAILURE" ]]; then
        update_config_value "$conf_file" "NOTIFY_ON_FAILURE" "$new_on_failure"
    fi
    if [[ "$NOTIFY_TYPE" == "telegram" ]]; then
        update_config_if_set "$conf_file" "TELEGRAM_BOT_TOKEN" "$new_bot_token"
        update_config_if_set "$conf_file" "TELEGRAM_CHAT_ID" "$new_chat_id"
    elif [[ "$NOTIFY_TYPE" == "email" ]]; then
        update_config_if_set "$conf_file" "SMTP_HOST" "$new_host"
        update_config_if_set "$conf_file" "SMTP_PORT" "$new_port"
        update_config_if_set "$conf_file" "SMTP_USER" "$new_user"
        update_config_if_set "$conf_file" "SMTP_PASS" "$new_pass"
        update_config_if_set "$conf_file" "FROM_ADDR" "$new_from"
        update_config_if_set "$conf_file" "TO_ADDR" "$new_to"
        update_config_if_set "$conf_file" "SMTP_TLS" "$new_tls"
    fi
    msg_ok "--- 配置修改完成 ---"
}
delete_single_notify_config() {
    local config_id="$1"
    local need_confirm="${2:-true}"
    local conf_file="${CONF_DIR}/${config_id}.conf"
    if [[ ! -f "$conf_file" ]]; then 
        msg_err "配置文件不存在: $conf_file"
        return
    fi
    local notify_type
    notify_type=$(get_value_from_conf "$conf_file" "NOTIFY_TYPE")
    msg_warn "删除通知配置 [ID: ${config_id}]"
    msg "类型: ${notify_type}"
    if [[ "$need_confirm" != "false" ]]; then
        local confirm
        prompt_for_yes_no "确定删除? 此操作无法撤销!" confirm "n"
        if [[ "$confirm" != "true" ]]; then
            msg_warn "已取消删除"
            return
        fi
    fi
    rm -f "$conf_file"
    msg_ok "通知配置 ${config_id} 删除成功"
}

delete_all_notify_configs() {
    msg_warn "警告: 将删除所有通知配置! 此操作无法撤销!"
    local confirm
    prompt_for_yes_no "确定继续?" confirm "n"
    if [[ "$confirm" != "true" ]]; then
        msg_warn "已取消删除"
        return
    fi
    for config_id in "$@"; do
        delete_single_notify_config "$config_id" "false"
    done
    msg_ok "所有通知配置删除成功"
}

test_single_notify_config() {
    conf_file="${CONF_DIR}/$1.conf"
    process_notify "$conf_file" "测试通知" "这是一条测试通知。\n\n如果您收到此消息，说明通知配置工作正常。"
}