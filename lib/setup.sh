#!/usr/bin/env bash

setup_notification_services() {
    local files_created=false
    local failure_service_path="${SYSTEMD_DIR}/service-failure-notify@.service"
    local success_service_path="${SYSTEMD_DIR}/service-success-notify@.service"

    if [[ ! -f "$failure_service_path" ]]; then
        msg_warn "通知服务 'service-failure-notify@.service' 不存在，正在创建..."
        cat > "$failure_service_path" << EOF
[Unit]
Description=Notify user of service failure for %i

[Service]
Type=oneshot
User=root
ExecStart=${SCRIPT_DIR}/service-failure-notify.sh %i
EOF
        files_created=true
        msg_ok "'service-failure-notify@.service' 已创建。"
    fi

    if [[ ! -f "$success_service_path" ]]; then
        msg_warn "通知服务 'service-success-notify@.service' 不存在，正在创建..."
        cat > "$success_service_path" << EOF
[Unit]
Description=Notify user of service success for %i

[Service]
Type=oneshot
User=root
ExecStart=${SCRIPT_DIR}/service-success-notify.sh %i
EOF
        files_created=true
        msg_ok "'service-success-notify@.service' 已创建。"
    fi

    if [[ "$files_created" == "true" ]]; then
        msg_info "检测到新的 systemd单元文件，正在重新加载 daemon..."
        systemctl daemon-reload
    fi
}

setup_master_backup_script() {
    local master_script_path="${SCRIPT_DIR}/run-backup.sh"
    if [[ -f "$master_script_path" ]]; then
        return 0
    fi

    msg_info "主备份脚本 '${master_script_path}' 不存在，正在创建..."
    cat > "$master_script_path" << 'EOF'
#!/usr/bin/env bash
set -e
set -o pipefail
if [[ -z "$1" ]]; then echo "错误：必须提供配置文件路径作为参数。" >&2; exit 1; fi
CONF_FILE="$1"
if [[ ! -f "$CONF_FILE" ]]; then echo "错误：配置文件 '${CONF_FILE}' 未找到。" >&2; exit 1; fi
set -a; source "$CONF_FILE"; set +a
RESTIC_BIN=$(command -v restic)
if [[ -z "$RESTIC_BIN" ]]; then echo "错误： 'restic' 命令未找到。" >&2; exit 1; fi
RESTIC_OPTS=""
if [[ -z "$RESTIC_PASSWORD" ]]; then RESTIC_OPTS="--insecure-no-password"; fi
echo "[\$(date)] -- 开始备份 (Config: ${CONF_FILE})"
$RESTIC_BIN $RESTIC_OPTS backup --verbose --files-from "${BACKUP_FILES_LIST}"
echo "[\$(date)] -- 开始清理旧备份 (Config: ${CONF_FILE})"
$RESTIC_BIN $RESTIC_OPTS forget --keep-daily "${KEEP_DAILY}" --keep-weekly "${KEEP_WEEKLY}" --prune
echo "[\$(date)] -- 备份完成 (Config: ${CONF_FILE})"
EOF
    chmod +x "$master_script_path"
    msg_ok "主备份脚本已创建并设为可执行。"
}