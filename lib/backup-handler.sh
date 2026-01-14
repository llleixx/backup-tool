#!/usr/bin/env bash
#
# 备份处理函数库

check_and_init_repository() {
    local repo="$1"
    local password="$2"
    msg_info "正在检查 repository 状态..."
    export RESTIC_REPOSITORY="$repo"
    export RESTIC_PASSWORD="$password"
    local restic_opts
    [[ -z "$password" ]] && restic_opts="--insecure-no-password" || restic_opts=""
    local exit_code
    set +e
    restic ${restic_opts} cat config &> /dev/null
    exit_code=$?
    set -e
    if [[ $exit_code -eq 10 ]]; then
        msg_warn "Repository 不存在 (exit code 10)，将尝试初始化..."
        if ! restic ${restic_opts} init; then
            msg_err "错误：初始化 repository 失败！请检查您的 rclone 配置或路径权限"
            unset RESTIC_REPOSITORY RESTIC_PASSWORD
            return 1
        fi
        msg_ok "Repository 初始化成功"
    elif [[ $exit_code -eq 11 ]]; then
        msg_err "错误：仓库上锁失败"
        unset RESTIC_REPOSITORY RESTIC_PASSWORD
        return 1
    elif [[ $exit_code -eq 12 ]]; then
        msg_err "错误：仓库已存在，密码不正确"
        unset RESTIC_REPOSITORY RESTIC_PASSWORD
        return 1
    elif [[ $exit_code -ne 0 ]]; then
        msg_err "错误：发生未知错误，restic 返回 exit code ${exit_code}"
        unset RESTIC_REPOSITORY RESTIC_PASSWORD
        return 1
    else
        msg_ok "Repository 已存在且凭据正确"
    fi
    unset RESTIC_REPOSITORY RESTIC_PASSWORD
    return 0
}

check_backup_dry_run() {
    local repo="$1"
    local password="$2"
    local backup_files_list="$3"
    msg_info "--- 正在进行备份试运行 (dry run) ---"
    export RESTIC_REPOSITORY="$repo"
    export RESTIC_PASSWORD="$password"
    local restic_opts
    [[ -z "$password" ]] && restic_opts="--insecure-no-password" || restic_opts=""
    if ! restic ${restic_opts} backup --files-from "$backup_files_list" --dry-run; then
        msg_err "错误：Dry run 失败，请检查文件列表路径 ('$backup_files_list') 或 repository 配置"
        unset RESTIC_REPOSITORY RESTIC_PASSWORD
        return 1
    fi
    msg_ok "Dry run 成功！配置看起来是有效的"
    unset RESTIC_REPOSITORY RESTIC_PASSWORD
    return 0
}

add_backup_config() {
    clear
    msg_info "--- 添加备份配置 ---"
    local repo backup_files_list password on_calendar keep_daily keep_weekly
    local pre_backup_hook post_success_hook post_failure_hook
    
    # 1. 备份文件列表路径
    while true; do
        prompt_for_input "备份文件列表路径 [默认: ${DEFAULT_BACKUP_LIST}]" backup_files_list true
        backup_files_list=${backup_files_list:-$DEFAULT_BACKUP_LIST}
        if [[ -f "$backup_files_list" ]]; then
            break
        fi
        local backup_dir
        backup_dir=$(dirname "$backup_files_list")
        if [[ ! -d "$backup_dir" ]]; then
            msg_warn "目录不存在: $backup_dir"
            continue
        fi
        msg_warn "文件不存在，正在创建: $backup_files_list"
        if ! echo -e "/opt/backup/conf\n/opt/backup/backup_list.txt" > "$backup_files_list"
        then
            msg_err "无法创建文件，请检查权限"
        else
            msg_ok "文件创建成功"
            break
        fi
    done
    
    # 2. Repository 地址
    prompt_for_input "Repository 地址 (如: rclone:remote:backup)" repo

    # 3. Repository 密码
    prompt_for_password "Repository 密码 (可留空)" password true
    
    # 4. 备份计划
    while true; do
        prompt_for_input "备份计划（OnCalendar）[默认: *-*-* 01:30:00 Asia/Shanghai]" on_calendar true
        on_calendar=${on_calendar:-"*-*-* 01:30:00 Asia/Shanghai"}
        if is_valid_oncalendar "$on_calendar"; then
            break
        else
            msg_warn "计划表达式无效，请参考 'man systemd.time'"
        fi
    done
    
    # 5. 保留策略
    prompt_for_number "保留天数 (daily) [默认: 7]" keep_daily true
    keep_daily=${keep_daily:-7}
    prompt_for_number "保留周数 (weekly) [默认: 4]" keep_weekly true
    keep_weekly=${keep_weekly:-4}

    # 6. Hook 脚本
    prompt_for_hook_path "备份前 hook 脚本路径" pre_backup_hook true
    prompt_for_hook_path "备份成功后 hook 脚本路径" post_success_hook true
    prompt_for_hook_path "备份失败后 hook 脚本路径" post_failure_hook true

    # 7. 验证配置
    check_and_init_repository "$repo" "$password" || return 1
    check_backup_dry_run "$repo" "$password" "$backup_files_list" || return 1
    
    # 8. 保存配置
    local config_id conf_file
    config_id=backup-$(generate_id)
    conf_file="${CONF_DIR}/${config_id}.conf"
    msg_info "保存配置: $conf_file"
    cat > "$conf_file" << EOF
CONFIG_ID="$config_id"
BACKUP_FILES_LIST="$backup_files_list"
RESTIC_REPOSITORY="$repo"
RESTIC_PASSWORD="$password"
ON_CALENDAR="$on_calendar"
KEEP_DAILY="$keep_daily"
KEEP_WEEKLY="$keep_weekly"
GROUP_BY="tags"
PRE_BACKUP_HOOK="$pre_backup_hook"
POST_SUCCESS_HOOK="$post_success_hook"
POST_FAILURE_HOOK="$post_failure_hook"
EOF
    msg_ok "配置保存成功"
    msg_info "应用系统服务..."
    apply_single_backup_config "$config_id"
    msg_info "--- 配置添加完成 ---"
    pause
}

change_single_backup_config() {
    local config_id="$1"
    local conf_file="${CONF_DIR}/${config_id}.conf"
    if [[ ! -f "$conf_file" ]]; then msg_err "配置文件不存在: $conf_file"; return 1; fi
    clear
    msg_info "--- 修改配置 [ID: ${config_id}] ---"
    # shellcheck source=/dev/null
    source "$conf_file"
    local new_repo new_pass new_list new_calendar new_daily new_weekly change_pass
    local new_pre_backup_hook new_post_success_hook new_post_failure_hook
    
    # 1. Repository
    prompt_for_input "Repository 地址 [当前: $RESTIC_REPOSITORY] (留空保留)" new_repo true
    
    # 2. 密码
    local change_pass
    prompt_for_yes_no "修改密码?" change_pass "n"
    if [[ "$change_pass" == "true" ]]; then
        prompt_for_password "新密码 (可留空)" new_pass true
    fi
    
    # 3. 文件列表
    while true; do
        prompt_for_input "备份文件列表路径 [当前: $BACKUP_FILES_LIST] (留空保留)" new_list true
        if [[ -z "$new_list" ]]; then
            break
        fi
        if [[ -f "$new_list" ]]; then
            break;
        fi
        local backup_dir
        backup_dir=$(dirname "$new_list")
        if [[ ! -d "$backup_dir" ]]; then
            msg_warn "目录不存在: $backup_dir"
            continue
        fi
        msg_warn "文件不存在，正在创建: $new_list"
        if ! echo -e "/opt/backup/conf\n/opt/backup/backup_list.txt" > "$new_list"
        then
            msg_err "无法创建文件，请检查权限"
        else
            msg_ok "文件创建成功"
            break
        fi
    done
    
    # 4. 备份计划
    while true; do
        prompt_for_input "备份计划（OnCalendar） [当前: $ON_CALENDAR] (留空保留)" new_calendar true
        if [[ -z "$new_calendar" ]]; then
            break
        fi
        if is_valid_oncalendar "$new_calendar"; then
            break;
        else
            msg_warn "计划表达式无效"
        fi
    done
    
    # 5. 保留策略
    prompt_for_number "保留天数 [当前: $KEEP_DAILY] (留空保留)" new_daily true
    prompt_for_number "保留周数 [当前: $KEEP_WEEKLY] (留空保留)" new_weekly true

    # 6. Hook 脚本
    prompt_for_hook_path "备份前 hook 脚本路径" new_pre_backup_hook true "$PRE_BACKUP_HOOK"
    prompt_for_hook_path "备份成功后 hook 脚本路径" new_post_success_hook true "$POST_SUCCESS_HOOK"
    prompt_for_hook_path "备份失败后 hook 脚本路径" new_post_failure_hook true "$POST_FAILURE_HOOK"
    
    # 7. 验证并保存配置
    if [[ -n "$new_repo" || "$change_pass" == "true" || -n "$new_list" ]]; then
        msg_info "验证新配置..."
        local final_repo final_pass final_list
        final_repo=${new_repo:-$RESTIC_REPOSITORY}
        final_pass=${new_pass:-$RESTIC_PASSWORD}
        final_list=${new_list:-$BACKUP_FILES_LIST}
        check_and_init_repository "$final_repo" "$final_pass" || { unset_config_vars; return 1; }
        check_backup_dry_run "$final_repo" "$final_pass" "$final_list" || { unset_config_vars; return 1; }
    fi

    msg_info "保存配置到 $conf_file"
    update_config_if_set "$conf_file" "RESTIC_REPOSITORY" "$new_repo"
    if [[ "$change_pass" == "true" ]]; then
        update_config_value "$conf_file" "RESTIC_PASSWORD" "$new_pass"
    fi
    update_config_if_set "$conf_file" "BACKUP_FILES_LIST" "$new_list"
    update_config_if_set "$conf_file" "ON_CALENDAR" "$new_calendar"
    update_config_if_set "$conf_file" "KEEP_DAILY" "$new_daily"
    update_config_if_set "$conf_file" "KEEP_WEEKLY" "$new_weekly"
    update_config_if_change "$conf_file" "PRE_BACKUP_HOOK" "$new_pre_backup_hook"
    update_config_if_change "$conf_file" "POST_SUCCESS_HOOK" "$new_post_success_hook"
    update_config_if_change "$conf_file" "POST_FAILURE_HOOK" "$new_post_failure_hook"
    
    unset_config_vars
    msg_ok "配置保存成功"
    msg_info "应用新配置到 systemd..."
    apply_single_backup_config "$config_id"
    msg_ok "--- 配置修改完成 ---"
}

_view_single_backup_config() {
    local config_id="$1"
    local conf_file="${CONF_DIR}/${config_id}.conf"
    if [[ ! -f "$conf_file" ]]; then msg_err "错误：找不到配置文件 $conf_file"; return; fi
    msg_info "--- 配置详情 [ID: ${config_id}] ---"
    (
        set -a; # shellcheck source=/dev/null
        source "$conf_file"; set +a;
        msg "  Repository:             $(msg_ok "${RESTIC_REPOSITORY}")"
        msg "  文件列表路径:           $(msg_ok "${BACKUP_FILES_LIST}")"
        msg "  计划任务 (OnCalendar):  $(msg_ok "${ON_CALENDAR}")"
        msg "  保留策略 (daily):       $(msg_ok "${KEEP_DAILY}")"
        msg "  保留策略 (weekly):      $(msg_ok "${KEEP_WEEKLY}")"
        msg "  备份前 hook:            $(msg_ok "${PRE_BACKUP_HOOK:-未设置}")"
        msg "  备份成功后 hook:        $(msg_ok "${POST_SUCCESS_HOOK:-未设置}")"
        msg "  备份失败后 hook:        $(msg_ok "${POST_FAILURE_HOOK:-未设置}")"
        msg "  密码:                   $(msg_warn "[已隐藏]")"
    )
    local timer_name="${config_id}.timer"
    msg_info "--- Systemd Timer 状态 [${timer_name}] ---"
    if ! systemctl cat "$timer_name" &> /dev/null; then
        msg "  状态:                   $(msg_warn "未找到 (可能尚未应用配置)")"
        return
    fi
    local status
    status=$(systemctl is-active "$timer_name" || echo "inactive")
    if [[ "$status" == "active" ]]; then
        msg "  状态:                   $(msg_ok "active (running)")"
    else
        msg "  状态:                   $(msg_warn "${status}")"
    fi
    local next_run
    next_run=$(systemctl list-timers "$timer_name" --no-legend | awk '{print $1, $2, $3, $4}')
    msg "  下一次运行时间:         $(msg_ok "${next_run}")"
}

view_single_backup_config() {
    clear
    _view_single_backup_config "$1"
}

view_all_backup_configs() {
    clear
    msg_info "--- 所有备份配置 ---"
    for config_id in "$@"; do
        _view_single_backup_config "$config_id"
        echo
    done
}

_delete_single_backup_config() {
    local config_id="$1"
    local need_confirm="${2:-true}"
    local conf_file="${CONF_DIR}/${config_id}.conf"
    if [[ ! -f "$conf_file" ]]; then msg_err "配置文件不存在: $conf_file"; return; fi
    local repo
    repo=$(get_value_from_conf "$conf_file" "RESTIC_REPOSITORY")
    msg_warn "删除配置 [ID: ${config_id}]"
    msg "Repository: $(msg_info "$repo")"
    if [[ "$need_confirm" != "false" ]]; then
        local confirm
        prompt_for_yes_no "确定删除? 此操作无法撤销!" confirm "n"
        if [[ "$confirm" != "true" ]]; then
            msg_warn "已取消删除"
            return
        fi
    fi
    msg_info "停止 systemd timer..."
    systemctl disable --now "${config_id}.timer" &>/dev/null || true
    msg_info "删除系统文件..."
    rm -f "${SYSTEMD_DIR}/${config_id}.service" "${SYSTEMD_DIR}/${config_id}.timer"
    msg_info "删除配置文件..."
    rm -f "$conf_file"
}

delete_single_backup_config() {
    local config_id="$1"
    _delete_single_backup_config "$config_id" true || return 1
    msg_info "重载 systemd daemon..."
    systemctl daemon-reload
    msg_ok "配置 ${config_id} 删除成功"
}

delete_all_backup_configs() {
    msg_warn "警告: 将删除所有备份配置! 此操作无法撤销!"
    local confirm
    prompt_for_yes_no "确定继续?" confirm "n"
    if [[ "$confirm" != "true" ]]; then
        msg_warn "已取消删除"
        return
    fi
    for config_id in "$@"; do
        _delete_single_backup_config "$config_id" false
    done
    msg_info "重载 systemd daemon..."
    systemctl daemon-reload
    msg_ok "所有备份配置删除成功"
}

apply_all_backup_configs() {
    msg_info "--- 开始应用所有备份配置 ---"
    local success_count=0 fail_count=0
    for config_id in "$@"; do
        if _apply_single_backup_config "$config_id"; then
            ((++success_count))
        else
            ((++fail_count))
        fi
    done
    _apply_config_post "$@"
    msg_ok "--- 应用所有配置完成 ---"
    msg_ok "成功应用 ${success_count} 个配置。"
    [[ $fail_count -gt 0 ]] && msg_err "失败 ${fail_count} 个配置。"
    return 0
}

_apply_single_backup_config() {
    local config_id="$1"
    msg_info "正在停止并禁用 ${config_id}.timer..."
    systemctl disable --now "${config_id}.timer" &>/dev/null || true
    msg_info "正在为 ID '${config_id}' 生成系统文件..."
    if ! generate_backup_system_files "$config_id"; then 
        msg_err "错误：生成系统文件失败"
        return 1
    fi
}

_apply_config_post() {
    msg_info "重新加载 systemd daemon..."
    systemctl daemon-reload
    for config_id in "$@"; do
        msg_info "正在启用并启动 ${config_id}.timer..."
        systemctl enable --now "${config_id}.timer"
    done
}

apply_single_backup_config() {
    local config_id="$1"
    if [[ -z "$config_id" ]]; then 
        msg_err "错误：缺少配置 ID 参数"
        return 1
    fi
    if ! _apply_single_backup_config "$config_id"; then return 1; fi
    _apply_config_post "$config_id"
    msg_ok "配置 ${config_id} 已成功应用"
}

generate_backup_system_files() {
    local config_id="$1"
    local conf_file="${CONF_DIR}/${config_id}.conf"
    if [[ ! -f "$conf_file" ]]; then msg_err "错误: 找不到配置文件 $conf_file"; return 1; fi
    local on_calendar
    on_calendar=$(get_value_from_conf "$conf_file" "ON_CALENDAR")
    local service_path="${SYSTEMD_DIR}/${config_id}.service"
    cat > "$service_path" << EOF
[Unit]
Description=Backup Service (ID: ${config_id})
OnFailure=service-failure-notify@%n
OnSuccess=service-success-notify@%n
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=${SCRIPT_DIR}/run-backup.sh ${conf_file}
User=root
Group=root
EOF
    local timer_path="${SYSTEMD_DIR}/${config_id}.timer"
    cat > "$timer_path" << EOF
[Unit]
Description=Run Backup Script (ID: ${config_id}) regularly
[Timer]
OnCalendar=${on_calendar}
Persistent=true
RandomizedDelaySec=15m
[Install]
WantedBy=timers.target
EOF
    return 0
}

backup_single_backup_config() {
    local config_id="$1"
    msg_info "正在为配置 ID '$config_id' 触发即时备份..."
    systemctl start "$config_id.service" &
    msg_ok "备份任务已触发，您可以使用 'journalctl -u ${config_id}.service -f' 来查看实时日志"
}

restore_single_backup_config() {
    local config_id="$1"
    local conf_file="${CONF_DIR}/${config_id}.conf"

    if [[ ! -f "$conf_file" ]]; then
        msg_err "错误：找不到配置文件 $conf_file"
        return 1
    fi

    clear
    msg_info "--- 从配置 [ID: ${config_id}] 恢复备份 ---"

    # 在子 Shell 中执行，避免环境变量泄漏
    (
        # shellcheck source=/dev/null
        source "$conf_file"

        export RESTIC_REPOSITORY
        export RESTIC_PASSWORD

        local restic_opts=""
        [[ -z "$RESTIC_PASSWORD" ]] && restic_opts="--insecure-no-password"

        msg_info "获取快照列表..."
        local snapshots_table
        snapshots_table=$(restic ${restic_opts} snapshots)
        if [[ -z "$snapshots_table" ]]; then
            msg_warn "此 Repository 中没有快照"
            return
        fi
        
        echo "$snapshots_table"
        echo

        # 从快照表格中提取所有有效的 short_id
        local valid_ids
        valid_ids=$(echo "$snapshots_table" | awk 'NR > 2 {print $1}')

        local snapshot_id
        while true; do
            prompt_for_input "快照 ID (短 ID)" snapshot_id
            # 检查输入的 ID 是否在有效 ID 列表中
            if echo "$valid_ids" | grep -q -w "$snapshot_id"; then
                break
            else
                msg_warn "无效的快照 ID: $snapshot_id"
            fi
        done

        local restore_path
        while true; do
            prompt_for_input "恢复到路径 (绝对路径)" restore_path
            if [[ "${restore_path:0:1}" == "/" ]]; then
                break
            else
                msg_warn "请输入绝对路径 (以 / 开头)"
            fi
        done

        msg_info "确认操作"
        msg "快照 ID: $(msg_ok "$snapshot_id")"
        msg "恢复路径: $(msg_ok "$restore_path")"
        msg_warn "警告: 可能会覆盖现有文件"
        
        local confirm
        prompt_for_yes_no "确定继续?" confirm "n"
        if [[ "$confirm" != "true" ]]; then
            msg_warn "已取消恢复"
            return
        fi

        msg_info "开始恢复..."
        if restic ${restic_opts} restore "$snapshot_id" --target "$restore_path"; then
            msg_ok "恢复成功!"
        else
            msg_err "恢复失败，请检查错误信息"
            return 1
        fi
    )
}
