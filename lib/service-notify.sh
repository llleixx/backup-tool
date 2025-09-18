#!/usr/bin/env bash
#
# /opt/backup/lib/service-notify.sh
#
# 通用通知调度库 (最终完善版)
#
# 工作流程:
# 1. 由 service-failure-notify.sh 或 service-success-notify.sh 调用。
# 2. 根据传入的事件类型 ("SUCCESS" 或 "FAILURE")，动态推断出
#    需要检查的配置变量 (NOTIFY_ON_...) 和需要调用的内容生成函数 (generate_..._notification)。
# 3. 执行一次内容生成函数，获取通知的标题和正文。
# 4. 遍历 /opt/backup/conf/notify-*.conf 目录下的所有配置文件。
# 5. 对于每个启用了相应通知的配置，根据其 NOTIFY_TYPE 调用对应的发送脚本
#    (如 notify-email.sh, notify-telegram.sh)，并将标题和正文传递给它。

set -euo pipefail

# --- 路径定义 ---
readonly ROOT_DIR="/opt/backup"
readonly SCRIPT_DIR="$ROOT_DIR/lib"
readonly CONF_DIR="$ROOT_DIR/conf"

# --- 核心调度函数 ---
# 参数:
# $1: unit_name (发生事件的 systemd 服务单元名称)
# $2: event_type ("SUCCESS" 或 "FAILURE")
process_event() {
    local unit_name="$1"
    local event_type="$2" # "SUCCESS" or "FAILURE"

    # --- 1. 根据事件类型动态推断变量名和函数名 ---
    local event_type_upper event_type_lower
    event_type_upper=$(echo "$event_type" | tr 'a-z' 'A-Z')
    event_type_lower=$(echo "$event_type" | tr 'A-Z' 'a-z')

    local check_variable="NOTIFY_ON_${event_type_upper}"
    local generator_func="generate_${event_type_lower}_notification"

    # --- 2. [健壮性检查] 检查内容生成函数是否存在且可执行 ---
    if ! declare -F "$generator_func" >/dev/null; then
        echo "致命错误: 内容生成函数 '$generator_func' 未定义或未导出。请检查调用方脚本。" >&2
        exit 1
    fi

    echo "检测到服务 '$unit_name' 事件。正在生成通知内容..." >&2

    # --- 3. 生成通知内容 (仅执行一次) ---
    local notification_content
    notification_content=$("$generator_func" "$unit_name")

    local subject body
    subject=$(echo "$notification_content" | head -n 1)
    body=$(echo "$notification_content" | tail -n +2)

    echo "内容生成完毕，开始遍历配置文件并分发..." >&2

    # --- 4. 遍历所有通知配置并进行分发 ---
    shopt -s nullglob
    for conf_file in "${CONF_DIR}"/notify-*.conf; do
        ( # 使用子 shell 处理每个配置，避免环境变量污染
            source "$conf_file"

            if [[ "${!check_variable:-false}" != "true" ]]; then
                exit 0
            fi

            echo "-> 正在为 '$conf_file' (类型: ${NOTIFY_TYPE:-未设置}) 分发通知..." >&2

            case "${NOTIFY_TYPE:-}" in
                email|telegram)
                    local sender_script="${SCRIPT_DIR}/notify-${NOTIFY_TYPE}.sh"
                    if [[ -x "$sender_script" ]]; then
                        echo "$body" | "$sender_script" "$conf_file" "$subject"
                    else
                        echo "错误: 发送脚本 '$sender_script' 未找到或不可执行。" >&2
                    fi
                    ;;
                "")
                    echo "错误: 配置文件 '$conf_file' 中未定义 NOTIFY_TYPE。" >&2
                    ;;
                *)
                    echo "警告: 配置文件 '$conf_file' 中定义了未知的 NOTIFY_TYPE: '${NOTIFY_TYPE}'。" >&2
                    ;;
            esac
        )
    done
    shopt -u nullglob

    echo "所有通知处理完成。" >&2
}