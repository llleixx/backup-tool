#!/usr/bin/env bash
#
# 通知处理函数库

prompt_for_smtp_tls() {
    local prompt_message="$1"
    local input_variable_name="$2"
    local allow_empty="${3:-false}"
    local user_input

    while true; do
        read -rp "$prompt_message: " user_input
        if [[ -z "$user_input" && "$allow_empty" == "true" ]]; then
            eval "$input_variable_name=\"\""
            return 0
        fi

        case "${user_input,,}" in
            1|starttls)
                eval "$input_variable_name=\"starttls\""
                return 0
                ;;
            2|on)
                eval "$input_variable_name=\"on\""
                return 0
                ;;
            3|off)
                eval "$input_variable_name=\"off\""
                return 0
                ;;
            *)
                msg_warn "无效的 TLS 类型，请输入 starttls/on/off 或 1/2/3。"
                ;;
        esac
    done
}

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
        config_write_json "$conf_file" "$(build_notify_config_json \
            "telegram" \
            "$notify_on_success" \
            "$notify_on_failure" \
            "$token" \
            "$chat_id")" || return 1
    elif [[ "$notify_type" == "email" ]]; then
        local smtp_host smtp_port smtp_user smtp_pass from_addr to_addr smtp_tls
        prompt_for_input "SMTP 服务器地址" smtp_host
        prompt_for_number "SMTP 服务器端口" smtp_port
        prompt_for_input "SMTP 用户名" smtp_user
        prompt_for_password "SMTP 密码/App Password" smtp_pass
        prompt_for_input "发件人地址" from_addr
        prompt_for_input "收件人地址" to_addr
        prompt_for_smtp_tls "TLS 类型 [1: starttls, 2: on(SMTPS), 3: off]" smtp_tls
        config_write_json "$conf_file" "$(build_notify_config_json \
            "email" \
            "$notify_on_success" \
            "$notify_on_failure" \
            "$smtp_host" \
            "$smtp_port" \
            "$smtp_user" \
            "$smtp_pass" \
            "$from_addr" \
            "$to_addr" \
            "$smtp_tls")" || return 1
    fi
    msg_ok "通知配置 '${conf_id}' 创建成功"
    msg_info "可以在“高级 -> 测试通知”中立即测试。"
    pause
}

_view_single_notify_config() {
    local config_id="$1"
    local conf_file="${CONF_DIR}/${config_id}.conf"
    if [[ ! -f "$conf_file" ]]; then 
        msg_err "错误: 找不到配置文件 $conf_file"
        return 1
    fi
    local notify_type notify_on_success notify_on_failure
    notify_type=$(config_get_optional "$conf_file" "NOTIFY_TYPE" "")
    notify_on_success=$(config_get_optional "$conf_file" "NOTIFY_ON_SUCCESS" "")
    notify_on_failure=$(config_get_optional "$conf_file" "NOTIFY_ON_FAILURE" "")
    msg_info "--- 通知配置详情 [ID: ${config_id}] ---"
    msg "  通知类型:           $(msg_ok "$notify_type")"
    msg "  成功时通知:         $(msg_ok "$notify_on_success")"
    msg "  失败时通知:         $(msg_ok "$notify_on_failure")"
    if [[ "$notify_type" == "telegram" ]]; then
        msg "  Bot Token:          $(msg_warn "[已隐藏]")"
        msg "  Chat ID:            $(msg_ok "$(config_get_optional "$conf_file" "TELEGRAM_CHAT_ID" "")")"
    elif [[ "$notify_type" == "email" ]]; then
        msg "  SMTP Host:          $(msg_ok "$(config_get_optional "$conf_file" "SMTP_HOST" "")")"
        msg "  SMTP Port:          $(msg_ok "$(config_get_optional "$conf_file" "SMTP_PORT" "")")"
        msg "  SMTP User:          $(msg_ok "$(config_get_optional "$conf_file" "SMTP_USER" "")")"
        msg "  SMTP Pass:          $(msg_warn "[已隐藏]")"
        msg "  发件人:             $(msg_ok "$(config_get_optional "$conf_file" "FROM_ADDR" "")")"
        msg "  收件人:             $(msg_ok "$(config_get_optional "$conf_file" "TO_ADDR" "")")"
        msg "  TLS:                $(msg_ok "$(config_get_optional "$conf_file" "SMTP_TLS" "")")"
    fi
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
    local NOTIFY_TYPE NOTIFY_ON_SUCCESS NOTIFY_ON_FAILURE
    local TELEGRAM_CHAT_ID SMTP_HOST SMTP_PORT SMTP_USER FROM_ADDR TO_ADDR SMTP_TLS
    NOTIFY_TYPE=$(config_get_required "$conf_file" "NOTIFY_TYPE") || return 1
    NOTIFY_ON_SUCCESS=$(config_get_optional "$conf_file" "NOTIFY_ON_SUCCESS" "true")
    NOTIFY_ON_FAILURE=$(config_get_optional "$conf_file" "NOTIFY_ON_FAILURE" "true")
    TELEGRAM_CHAT_ID=$(config_get_optional "$conf_file" "TELEGRAM_CHAT_ID" "")
    SMTP_HOST=$(config_get_optional "$conf_file" "SMTP_HOST" "")
    SMTP_PORT=$(config_get_optional "$conf_file" "SMTP_PORT" "")
    SMTP_USER=$(config_get_optional "$conf_file" "SMTP_USER" "")
    FROM_ADDR=$(config_get_optional "$conf_file" "FROM_ADDR" "")
    TO_ADDR=$(config_get_optional "$conf_file" "TO_ADDR" "")
    SMTP_TLS=$(config_get_optional "$conf_file" "SMTP_TLS" "starttls")
    
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
        prompt_for_smtp_tls "TLS 类型 [当前: $SMTP_TLS] (留空保留)" new_tls true
    fi

    msg_info "保存配置到 $conf_file"
    migrate_config_file_if_needed "$conf_file" || return 1
    if [[ "$new_on_success" != "$NOTIFY_ON_SUCCESS" ]]; then
        update_config_value "$conf_file" "NOTIFY_ON_SUCCESS" "$new_on_success" || return 1
    fi
    if [[ "$new_on_failure" != "$NOTIFY_ON_FAILURE" ]]; then
        update_config_value "$conf_file" "NOTIFY_ON_FAILURE" "$new_on_failure" || return 1
    fi
    if [[ "$NOTIFY_TYPE" == "telegram" ]]; then
        update_config_if_set "$conf_file" "TELEGRAM_BOT_TOKEN" "$new_bot_token" || return 1
        update_config_if_set "$conf_file" "TELEGRAM_CHAT_ID" "$new_chat_id" || return 1
    elif [[ "$NOTIFY_TYPE" == "email" ]]; then
        update_config_if_set "$conf_file" "SMTP_HOST" "$new_host" || return 1
        update_config_if_set "$conf_file" "SMTP_PORT" "$new_port" || return 1
        update_config_if_set "$conf_file" "SMTP_USER" "$new_user" || return 1
        update_config_if_set "$conf_file" "SMTP_PASS" "$new_pass" || return 1
        update_config_if_set "$conf_file" "FROM_ADDR" "$new_from" || return 1
        update_config_if_set "$conf_file" "TO_ADDR" "$new_to" || return 1
        update_config_if_set "$conf_file" "SMTP_TLS" "$new_tls" || return 1
    fi
    msg_ok "--- 配置修改完成 ---"
}
delete_single_notify_config() {
    local config_id="$1"
    local need_confirm="${2:-true}"
    local conf_file="${CONF_DIR}/${config_id}.conf"
    if [[ ! -f "$conf_file" ]]; then 
        msg_err "配置文件不存在: $conf_file"
        return 1
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
            return 0
        fi
    fi
    rm -f "$conf_file"
    msg_ok "通知配置 ${config_id} 删除成功"
    return 0
}

delete_all_notify_configs() {
    msg_warn "警告: 将删除所有通知配置! 此操作无法撤销!"
    local confirm
    local success_count=0 fail_count=0
    prompt_for_yes_no "确定继续?" confirm "n"
    if [[ "$confirm" != "true" ]]; then
        msg_warn "已取消删除"
        return
    fi
    for config_id in "$@"; do
        if delete_single_notify_config "$config_id" "false"; then
            ((++success_count))
        else
            ((++fail_count))
        fi
    done
    msg_ok "成功删除 ${success_count} 个通知配置。"
    [[ $fail_count -gt 0 ]] && msg_err "删除失败 ${fail_count} 个通知配置。"
    [[ $fail_count -eq 0 ]]
}

test_single_notify_config() {
    local conf_file="${CONF_DIR}/$1.conf"
    process_notify "$conf_file" "🟡 [Test] 测试通知" $'这是一条测试通知'
}
