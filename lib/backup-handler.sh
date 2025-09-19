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
            msg_err "错误：初始化 repository 失败！请检查您的 rclone 配置或路径权限。"
            unset RESTIC_REPOSITORY RESTIC_PASSWORD
            return 1
        fi
        msg_ok "Repository 初始化成功。"
    elif [[ $exit_code -eq 1 ]]; then
        msg_err "错误：访问 repository 失败 (exit code 1)。可能是密码错误或其它连接问题。"
        unset RESTIC_REPOSITORY RESTIC_PASSWORD
        return 1
    elif [[ $exit_code -ne 0 ]]; then
        msg_err "错误：发生未知错误，restic 返回 exit code ${exit_code}。"
        unset RESTIC_REPOSITORY RESTIC_PASSWORD
        return 1
    else
        msg_ok "Repository 已存在且凭据正确。"
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
        msg_err "错误：Dry run 失败。请检查文件列表路径 ('$backup_files_list') 或 repository 配置。"
        unset RESTIC_REPOSITORY RESTIC_PASSWORD
        return 1
    fi
    msg_ok "Dry run 成功！配置看起来是有效的。"
    unset RESTIC_REPOSITORY RESTIC_PASSWORD
    return 0
}

add_backup_config() {
    msg_info "--- 开始添加新的备份配置 ---"
    local repo backup_files_list password password_confirm on_calendar keep_daily keep_weekly restic_opts host
    while true; do
        read -rp "请输入备份文件列表的路径 [默认: ${DEFAULT_BACKUP_LIST}]: " backup_files_list
        backup_files_list=${backup_files_list:-$DEFAULT_BACKUP_LIST}
        if [[ -f "$backup_files_list" ]]; then
            break
        else
            msg_warn "警告: 文件 '$backup_files_list' 不存在。请先创建该文件并列出要备份的路径。"
        fi
    done
    host=$(uname -n | cut -d'.' -f1)
    while true; do
        read -rp "请输入 restic repository (例如: rclone:remote:backup-$host): " repo
        if [[ -n "$repo" ]]; then
            break;
        else
            msg_warn "Repository 不能为空，请重新输入。"
        fi
    done
    while true; do
        read -rsp "请输入 repository 密码 (可留空): " password
        echo
        read -rsp "请再次输入密码以确认: " password_confirm
        echo
        if [[ "$password" != "$password_confirm" ]]; then msg_warn "两次输入的密码不匹配，请重新输入。";
        else break; fi
    done
    while true; do
        read -rp "请输入 systemd OnCalendar 表达式 [默认: *-*-* 01:30:00 Asia/Shanghai]: " on_calendar
        on_calendar=${on_calendar:-"*-*-* 01:30:00 Asia/Shanghai"}
        if is_valid_oncalendar "$on_calendar"; then
            break
        else
            msg_warn "表达式 '$on_calendar' 无效，请参考 'man systemd.time' 并重试。"
        fi
    done
    while true; do 
        read -rp "请输入 forget --keep-daily 的天数 [例如: 7]: " keep_daily;
        if [[ "$keep_daily" =~ ^[0-9]+$ ]]; then
            break
        else
            msg_warn "请输入一个有效的数字。"; 
        fi
    done
    while true; do
        read -rp "请输入 forget --keep-weekly 的周数 [例如: 4]: " keep_weekly;
        if [[ "$keep_weekly" =~ ^[0-9]+$ ]]; then
            break
        else
            msg_warn "请输入一个有效的数字。";
        fi
    done
    check_and_init_repository "$repo" "$password" || return 1
    check_backup_dry_run "$repo" "$password" "$backup_files_list" || return 1
    local config_id conf_file
    config_id=backup-$(generate_id)
    conf_file="${CONF_DIR}/${config_id}.conf"
    msg_info "正在生成配置文件: $conf_file"
    cat > "$conf_file" << EOF
# Restic Backup Configuration
CONFIG_ID="$config_id"
BACKUP_FILES_LIST="$backup_files_list"
RESTIC_REPOSITORY="$repo"
RESTIC_PASSWORD="$password"
ON_CALENDAR="$on_calendar"
KEEP_DAILY="$keep_daily"
KEEP_WEEKLY="$keep_weekly"
GROUP_BY="tags"
EOF
    msg_ok "配置文件已保存。"
    msg_info "正在生成并应用系统服务文件..."
    apply_single_backup_config "$config_id"
    msg_info "--- 新配置添加完成 ---"
    pause
}

change_single_backup_config() {
    local config_id="$1"
    local conf_file="${CONF_DIR}/${config_id}.conf"
    if [[ ! -f "$conf_file" ]]; then msg_err "错误：找不到配置文件 $conf_file"; return 1; fi
    clear
    msg_info "--- 更改配置 [ID: ${config_id}] ---"
    # shellcheck source=/dev/null
    source "$conf_file"
    local new_repo new_pass new_pass_confirm new_list new_calendar new_daily new_weekly change_pass
    msg "1. Repository"
    msg "   当前值: $(msg_ok "$RESTIC_REPOSITORY")"
    read -rp "   输入新值或按 Enter 保留: " new_repo
    new_repo=${new_repo:-$RESTIC_REPOSITORY}
    msg "\n2. 密码"
    read -rp "   是否要更改密码? [y/N]: " change_pass
    if [[ "${change_pass,,}" == "y" ]]; then
        while true; do
            read -rsp "   请输入新密码 (可留空): " new_pass; echo
            read -rsp "   请再次输入密码以确认: " new_pass_confirm; echo
            if [[ "$new_pass" != "$new_pass_confirm" ]]; then msg_warn "   两次输入的密码不匹配。";
            else break; fi
        done
        else
            new_pass="$RESTIC_PASSWORD"
    fi
    msg "\n3. 备份文件列表路径"
    while true; do
        read -rp "   输入新值或按 Enter 保留 [当前: $BACKUP_FILES_LIST]: " new_list
        new_list=${new_list:-$BACKUP_FILES_LIST}
        if [[ -f "$new_list" ]]; then
            break;
        else
            msg_warn "   文件 '$new_list' 不存在，请重新输入。"
        fi
    done
    msg "\n4. 计划任务 (OnCalendar)"
    while true; do
        read -rp "   输入新值或按 Enter 保留 [当前: $ON_CALENDAR]: " new_calendar
        new_calendar=${new_calendar:-$ON_CALENDAR}
        if is_valid_oncalendar "$new_calendar"; then
            break;
        else
            msg_warn "   表达式 '$new_calendar' 无效，请重试。"
        fi
    done
    msg "\n5. 保留策略"
    while true; do
        read -rp "   保留 daily 天数 [当前: $KEEP_DAILY]: " new_daily
        new_daily=${new_daily:-$KEEP_DAILY}
        [[ "$new_daily" =~ ^[0-9]+$ ]] && break || msg_warn "   请输入一个有效的数字。"
    done
    while true; do
        read -rp "   保留 weekly 周数 [当前: $KEEP_WEEKLY]: " new_weekly
        new_weekly=${new_weekly:-$KEEP_WEEKLY}
        [[ "$new_weekly" =~ ^[0-9]+$ ]] && break || msg_warn "   请输入一个有效的数字。"
    done
    msg_info "\n--- 正在验证新配置 ---"
    check_and_init_repository "$new_repo" "$new_pass" || { unset_config_vars; return 1; }
    check_backup_dry_run "$new_repo" "$new_pass" "$new_list" || { unset_config_vars; return 1; }
    msg_info "\n正在保存更改到 $conf_file..."
    cat > "$conf_file" << EOF
# Restic Backup Configuration
CONFIG_ID="$config_id"
BACKUP_FILES_LIST="$new_list"
RESTIC_REPOSITORY="$new_repo"
RESTIC_PASSWORD="$new_pass"
ON_CALENDAR="$new_calendar"
KEEP_DAILY="$new_daily"
KEEP_WEEKLY="$new_weekly"
EOF
    unset_config_vars
    msg_ok "配置已保存。"
    msg_info "\n正在应用新配置到 systemd..."
    apply_single_backup_config "$config_id"
    msg_ok "--- 配置更改完成 ---"
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
    if [[ ! -f "$conf_file" ]]; then msg_err "错误：找不到配置文件 $conf_file"; return; fi
    local repo
    repo=$(get_value_from_conf "$conf_file" "RESTIC_REPOSITORY")
    msg_warn "\n--- 删除配置 [ID: ${config_id}] ---"
    msg "您将要删除以下配置:"
    msg "  Repository: $(msg_info "$repo")"
    if [[ "$need_confirm" != "false" ]]; then
        local confirm
        read -rp "您确定要永久删除此配置及其关联的所有文件吗？此操作无法撤销！[y/N]: " confirm
        if [[ "${confirm,,}" != "y" ]]; then
            msg_warn "删除操作已取消。"
            return
        fi
    fi
    msg_info "正在停止并禁用 systemd timer..."
    systemctl disable --now "${config_id}.timer" &>/dev/null || true
    msg_info "正在删除 systemd 服务和定时器文件..."
    rm -f "${SYSTEMD_DIR}/${config_id}.service" "${SYSTEMD_DIR}/${config_id}.timer"
    msg_info "正在删除配置文件..."
    rm -f "$conf_file"
}

delete_single_backup_config() {
    local config_id="$1"
    _delete_single_backup_config "$config_id" true || return 1
    msg_info "正在重新加载 systemd daemon..."
    systemctl daemon-reload
    msg_ok "配置 ${config_id} 已成功删除。"
}

delete_all_backup_configs() {
    msg_warn "警告: 您将删除所有备份配置及其关联的文件！此操作无法撤销！"
    local confirm
    read -rp "您确定要继续吗？[y/N]: " confirm
    if [[ "${confirm,,}" != "y" ]]; then
        msg_warn "删除操作已取消。"
        return
    fi
    for config_id in "$@"; do
        _delete_single_backup_config "$config_id" false
    done
    msg_info "正在重新加载 systemd daemon..."
    systemctl daemon-reload
    msg_ok "所有备份配置已成功删除。"
}

apply_all_backup_configs() {
    msg_info "--- 开始应用所有备份配置 ---"
    local success_count=0 fail_count=0
    for config_id in "$@"; do
        if _apply_single_backup_config "$config_id"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
    done
    _apply_config_post "$@"
    msg_ok "--- 应用所有配置完成 ---"
    msg_ok "成功应用 ${success_count} 个配置。"
    [[ $fail_count -gt 0 ]] && msg_err "失败 ${fail_count} 个配置。"
}

_apply_single_backup_config() {
    local config_id="$1"
    msg_info "正在停止并禁用 ${config_id}.timer..."
    systemctl disable --now "${config_id}.timer" &>/dev/null || true
    msg_info "正在为 ID '${config_id}' 生成系统文件..."
    if ! generate_backup_system_files "$config_id"; then msg_err "错误：生成系统文件失败。"; return 1; fi
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
    if [[ -z "$config_id" ]]; then msg_err "错误：缺少配置 ID 参数。"; return 1; fi
    if ! _apply_single_backup_config "$config_id"; then return 1; fi
    _apply_config_post "$config_id"
    msg_ok "配置 ${config_id} 已成功应用。"
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
Description=Restic Backup Service (ID: ${config_id})
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
Description=Run Restic Backup Script (ID: ${config_id}) regularly
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
    msg_ok "备份任务已触发，您可以使用 'journalctl -u ${config_id}.service -f' 来查看实时日志。"
}

restore_single_backup_config() {
    local config_id="$1"
    local conf_file="${CONF_DIR}/${config_id}.conf"

    if [[ ! -f "$conf_file" ]]; then
        msg_err "错误：找不到配置文件 $conf_file"
        return 1
    fi

    clear
    msg_info "--- 开始从配置 [ID: ${config_id}] 恢复备份 ---"

    # 在子 Shell 中执行，避免环境变量泄漏
    (
        # shellcheck source=/dev/null
        source "$conf_file"

        export RESTIC_REPOSITORY
        export RESTIC_PASSWORD

        local restic_opts
        [[ -z "$RESTIC_PASSWORD" ]] && restic_opts="--insecure-no-password"

        msg_info "正在获取快照列表..."
        local snapshots_table
        snapshots_table=$(restic ${restic_opts} snapshots)
        if [[ -z "$snapshots_table" ]]; then
            msg_warn "此 Repository 中没有任何快照。"
            return
        fi
        
        echo "$snapshots_table"
        echo

        # 从快照表格中提取所有有效的 short_id
        local valid_ids
        valid_ids=$(echo "$snapshots_table" | awk 'NR > 2 {print $1}')

        local snapshot_id
        while true; do
            read -rp "请输入要还原的快照 ID (短 ID): " snapshot_id
            # 检查输入的 ID 是否在有效 ID 列表中
            if echo "$valid_ids" | grep -q -w "$snapshot_id"; then
                break
            else
                msg_warn "无效的快照 ID '$snapshot_id'，请从上面的列表中选择一个有效的 ID。"
            fi
        done

        local restore_path
        while true; do
            read -rp "请输入要将文件还原到的绝对路径: " restore_path
            if [[ -n "$restore_path" && "${restore_path:0:1}" == "/" ]]; then
                break
            else
                msg_warn "请输入一个有效的绝对路径 (以 / 开头)。"
            fi
        done

        msg_info "\n--- 确认操作 ---"
        msg "快照 ID:    $(msg_ok "$snapshot_id")"
        msg "还原路径:   $(msg_ok "$restore_path")"
        msg_warn "警告：如果还原路径已存在文件，Restic 可能会覆盖它们。"
        
        local confirm
        read -rp "您确定要继续吗？[y/N]: " confirm
        if [[ "${confirm,,}" != "y" ]]; then
            msg_warn "还原操作已取消。"
            return
        fi

        msg_info "\n正在开始还原..."
        if restic ${restic_opts} restore "$snapshot_id" --target "$restore_path"; then
            msg_ok "还原成功！"
        else
            msg_err "还原失败。请检查上面的错误信息。"
            return 1
        fi
    )
}