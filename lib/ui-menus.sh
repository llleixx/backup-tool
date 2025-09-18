#!/usr/bin/env bash

# --- 请将您原始脚本中对应的菜单函数代码复制到这里 ---
select_backup_config_menu() {
    local title="$1"
    local callback_single="$2"
    local callback_all="$3"
    local prefix="backup-"
    local configs_map=()
    local config_ids=()
    for conf_file in "${CONF_DIR}"/"$prefix"*.conf; do
        [[ -f "$conf_file" ]] || continue
        local id repo
        id=$(basename "$conf_file" .conf)
        repo=$(get_value_from_conf "$conf_file" "RESTIC_REPOSITORY")
        configs_map+=("ID: ${id} (Repo: ${repo})")
        config_ids+=("$id")
    done
    if [[ ${#configs_map[@]} -eq 0 ]]; then
        msg_warn "配置目录 '${CONF_DIR}' 中没有任何 '${prefix}*.conf' 文件。"
        pause; return
    fi
    clear
    msg_info "--- ${title} ---"
    msg "请选择一个配置:"
    local i=1
    for item in "${configs_map[@]}"; do
        msg " ${i}) ${item}"
        ((i++))
    done
    if [[ -n "$callback_all" ]]; then msg_ok " a) 所有配置"; fi
    msg_warn " b) 返回"
    local choice
    read -rp "输入您的选择: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#configs_map[@]} ]; then
        local selected_id=${config_ids[$choice-1]}
        "$callback_single" "$selected_id"
    elif [[ -n "$callback_all" && "${choice,,}" == "a" ]]; then
        "$callback_all" "${config_ids[@]}"
    elif [[ "${choice,,}" == "b" ]]; then
        return
    else
        msg_err "无效的选择。"
    fi
    pause
}
select_notify_config_menu() {
    local title="$1"
    local callback_single="$2"
    local callback_all="$3"
    local prefix="notify-"
    local configs_map=()
    local config_ids=()
    for conf_file in "${CONF_DIR}"/"$prefix"*.conf; do
        [[ -f "$conf_file" ]] || continue
        local id type dest
        id=$(basename "$conf_file" .conf)
        type=$(get_value_from_conf "$conf_file" "NOTIFY_TYPE")
        if [[ "$type" == "telegram" ]]; then
            dest=$(get_value_from_conf "$conf_file" "TELEGRAM_CHAT_ID")
        else
            dest=$(get_value_from_conf "$conf_file" "TO_ADDR")
        fi
        configs_map+=("ID: ${id} (Type: ${type}, To: ${dest})")
        config_ids+=("$id")
    done
    if [[ ${#configs_map[@]} -eq 0 ]]; then
        msg_warn "配置目录 '${CONF_DIR}' 中没有任何 '${prefix}*.conf' 文件。"
        pause; return
    fi
    clear
    msg_info "--- ${title} ---"
    msg "请选择一个通知配置:"
    local i=1
    for item in "${configs_map[@]}"; do
        msg " ${i}) ${item}"
        ((i++))
    done
    if [[ -n "$callback_all" ]]; then msg_ok " a) 所有配置"; fi
    msg_warn " b) 返回"
    local choice
    read -rp "输入您的选择: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#configs_map[@]} ]; then
        local selected_id=${config_ids[$choice-1]}
        "$callback_single" "$selected_id"
    elif [[ -n "$callback_all" && "${choice,,}" == "a" ]]; then
        "$callback_all" "${config_ids[@]}"
    elif [[ "${choice,,}" == "b" ]]; then
        return
    else
        msg_err "无效的选择。"
    fi
    pause
}
show_notify_menu() {
    while true; do
        clear
        msg_info "=========================================="
        msg_info " 通知配置管理 "
        msg_info "=========================================="
        msg_ok " 1. 添加通知配置"
        msg_ok " 2. 更改通知配置"
        msg_ok " 3. 查看通知配置"
        msg_ok " 4. 删除通知配置"
        msg_warn " b. 返回主菜单"
        msg_info "------------------------------------------"
        read -rp "输入您的选择: " choice
        case "$choice" in
            1) add_notify_config ;;
            2) select_notify_config_menu "更改通知菜单" "change_single_notify_config" ;;
            3) select_notify_config_menu "查看通知菜单" "view_single_notify_config" "view_all_notify_configs" ;;
            4) select_notify_config_menu "删除通知菜单" "delete_single_notify_config" ;;
            b|B) break ;;
            *) msg_warn "无效的输入，请重新选择。"; sleep 1 ;;
        esac
    done
}
show_menu() {
    clear
    msg_info "=========================================="
    msg_info " Backup Tool "
    msg_info "=========================================="
    msg "请选择一个操作:"
    msg_ok " 1. 添加备份配置"
    msg_ok " 2. 更改备份配置"
    msg_ok " 3. 查看备份配置"
    msg_ok " 4. 删除备份配置"
    msg_ok " 5. 应用备份配置"
    msg_ok " 6. 添加通知配置"
    msg_ok " 7. 更改通知配置"
    msg_ok " 8. 查看通知配置"
    msg_ok " 9. 删除通知配置"
    msg_ok "10. 高级"
    msg " q. 退出"
    msg_info "------------------------------------------"
}
advanced_settings_menu() {
    while true; do
        clear
        msg_info "=========================================="
        msg_info " 高级菜单 "
        msg_info "=========================================="
        msg_ok " 1. 立即备份"
        msg_ok " 2. 恢复备份"
        msg_ok " 3. 通知测试"
        msg_ok " 4. rclone 安装"
        msg_warn " b. 返回主菜单"
        msg_info "------------------------------------------"
        read -rp "输入您的选择: " choice
        case "$choice" in
            1) select_backup_config_menu "立即备份菜单" "backup_single_backup_config" ;;
            2) select_backup_config_menu "恢复备份菜单" "restore_single_backup_config" ;;
            3) select_notify_config_menu "通知测试菜单" "test_single_notify_config" ;;
            b|B) break ;;
            *) msg_warn "无效的输入，请重新选择。"; sleep 1 ;;
        esac
    done
}