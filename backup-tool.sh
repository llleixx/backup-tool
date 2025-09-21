#!/usr/bin/env bash

# Backup Tool
# 主执行文件

# --- 全局设置 ---
set -euo pipefail -E
trap 'error_handler' ERR

error_handler() {
  local exit_code=$?
  local line_no=${BASH_LINENO[0]}
  local command="${BASH_COMMAND}"
  local func_name="${FUNCNAME[1]}"

  msg_err "--------------------------------------------------"
  msg_err "ERROR: 命令 '$command' 在脚本 '${BASH_SOURCE[1]}' 的函数 '$func_name' 第 $line_no 行失败，退出码为 $exit_code"
  msg_err "--------------------------------------------------"
}

# 获取脚本所在目录，确保可以正确加载库文件
readonly _ROOT_DIR="/opt/backup"

# --- 加载库文件 ---
source "${_ROOT_DIR}/lib/config.sh"
source "${_ROOT_DIR}/lib/utils.sh"
source "${_ROOT_DIR}/lib/service-notify.sh"
source "${_ROOT_DIR}/lib/backup-handler.sh"
source "${_ROOT_DIR}/lib/notify-handler.sh"
source "${_ROOT_DIR}/lib/ui-menus.sh"

# --- 主逻辑 ---
main() {
    # 初始化检查
    check_root

    # 进入主菜单循环
    while true; do
        show_menu
        local choice
        prompt_for_input "选择" choice
        case "$choice" in
            1) add_backup_config ;;
            2) select_backup_config_menu "修改备份配置" "change_single_backup_config" ;;
            3) select_backup_config_menu "查看备份配置" "view_single_backup_config" "view_all_backup_configs" ;;
            4) select_backup_config_menu "删除备份配置" "delete_single_backup_config" "delete_all_backup_configs" ;;
            5) select_backup_config_menu "应用备份配置" "apply_single_backup_config" "apply_all_backup_configs";;
            6) add_notify_config ;;
            7) select_notify_config_menu "修改通知配置" "change_single_notify_config" ;;
            8) select_notify_config_menu "查看通知配置" "view_single_notify_config" "view_all_notify_configs" ;;
            9) select_notify_config_menu "删除通知配置" "delete_single_notify_config" "delete_all_notify_configs" ;;
            10) advanced_settings_menu ;;
            11) uninstall_script ;;
            q|Q) msg_info "退出脚本"; break ;;
            *) msg_warn "无效选择"; sleep 1 ;;
        esac
    done
}

# --- 脚本执行入口 ---
main "$@"