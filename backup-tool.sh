#!/usr/bin/env bash

# Backup Tool
# 主执行文件

# --- 全局设置 ---
set -e
set -o pipefail

# 获取脚本所在目录，确保可以正确加载库文件
readonly SCRIPT_BASE_DIR="/opt/backup"

# --- 加载库文件 ---
source "${SCRIPT_BASE_DIR}/lib/config.sh"
source "${SCRIPT_BASE_DIR}/lib/utils.sh"
source "${SCRIPT_BASE_DIR}/lib/setup.sh"
source "${SCRIPT_BASE_DIR}/lib/backup-handler.sh"
source "${SCRIPT_BASE_DIR}/lib/notify-handler.sh"
source "${SCRIPT_BASE_DIR}/lib/ui-menus.sh"

# --- 主逻辑 ---
main() {
    # 初始化检查
    check_root
    check_dependency "restic"
    check_dependency "systemd-analyze"
    check_restic_version

    # 确保基础目录和脚本存在
    mkdir -p "$CONF_DIR" "$SCRIPT_DIR"
    setup_notification_services
    setup_master_backup_script

    # 进入主菜单循环
    while true; do
        show_menu
        read -rp "输入您的选择: " choice
        case "$choice" in
            1) add_backup_config ;;
            2) select_backup_config_menu "更改备份菜单" "change_single_backup_config";;
            3) select_backup_config_menu "查看备份菜单" "view_single_backup_config" "view_all_backup_configs";;
            4) select_backup_config_menu "删除备份菜单" "delete_single_backup_config";;
            5) select_backup_config_menu "应用备份菜单" "apply_single_backup_config" "apply_all_backup_configs";;
            6) add_notify_config ;;
            7) select_notify_config_menu "更改通知菜单" "change_single_notify_config" ;;
            8) select_notify_config_menu "查看通知菜单" "view_single_notify_config" "view_all_notify_configs" ;;
            9) select_notify_config_menu "删除通知菜单" "delete_single_notify_config" ;;
            10) advanced_settings_menu ;;
            q|Q) msg_info "退出脚本。"; break ;;
            *) msg_warn "无效的输入，请重新选择。"; sleep 1 ;;
        esac
    done
}

# --- 脚本执行入口 ---
main "$@"