#!/usr/bin/env bash
#
# systemd unit helpers

if [[ -n "${BACKUP_TOOL_SYSTEMD_UNITS_SH_LOADED:-}" ]]; then
    # shellcheck disable=SC2317
    return 0 2>/dev/null || exit 0
fi
readonly BACKUP_TOOL_SYSTEMD_UNITS_SH_LOADED=1

backup_service_template_path() {
    printf '%s/backup-tool@.service' "$SYSTEMD_DIR"
}

backup_systemd_instance_name() {
    local config_id="$1"
    printf '%s' "${config_id#backup-}"
}

backup_service_unit_name() {
    local config_id="$1"
    printf 'backup-tool@%s.service' "$(backup_systemd_instance_name "$config_id")"
}

backup_timer_unit_name() {
    local config_id="$1"
    printf 'backup-tool@%s.timer' "$(backup_systemd_instance_name "$config_id")"
}

write_systemd_unit() {
    local unit_path="$1"
    local unit_dir unit_name tmp_file

    unit_dir=$(dirname "$unit_path")
    unit_name=$(basename "$unit_path")
    tmp_file=$(mktemp -p "$unit_dir" ".${unit_name}.tmp.XXXXXX")

    cat > "$tmp_file"
    chmod 0644 "$tmp_file"
    mv "$tmp_file" "$unit_path"
}

install_backup_service_template() {
    write_systemd_unit "$(backup_service_template_path)" << EOF
[Unit]
Description=Backup Tool job (%i)
Documentation=https://github.com/${REPO}
OnFailure=service-failure-notify@%i.service
OnSuccess=service-success-notify@%i.service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${SCRIPT_DIR}/run-backup.sh ${CONF_DIR}/backup-%i.conf
User=root
Group=root
EOF
}

write_backup_timer_unit() {
    local config_id="$1"
    local on_calendar="$2"
    local timer_path

    timer_path="${SYSTEMD_DIR}/$(backup_timer_unit_name "$config_id")"

    write_systemd_unit "$timer_path" << EOF
[Unit]
Description=Run Backup Script (ID: ${config_id}) regularly
[Timer]
OnCalendar=${on_calendar}
Persistent=true
RandomizedDelaySec=15m
Unit=$(backup_service_unit_name "$config_id")
[Install]
WantedBy=timers.target
EOF
}

install_notification_service_templates() {
    write_systemd_unit "${SYSTEMD_DIR}/service-failure-notify@.service" << EOF
[Unit]
Description=Notify user of service failure for %i

[Service]
Type=oneshot
User=root
ExecStart=${SCRIPT_DIR}/service-failure-notify.sh %i
EOF

    write_systemd_unit "${SYSTEMD_DIR}/service-success-notify@.service" << EOF
[Unit]
Description=Notify user of service success for %i

[Service]
Type=oneshot
User=root
ExecStart=${SCRIPT_DIR}/service-success-notify.sh %i
EOF
}

install_systemd_unit_templates() {
    install_backup_service_template
    install_notification_service_templates
    systemctl daemon-reload
}
