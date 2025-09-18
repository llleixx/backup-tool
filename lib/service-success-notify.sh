#!/usr/bin/env bash
#
# /opt/backup/service-success-notify.sh
# 内容生成器：为成功事件生成通知标题和正文。

set -euo pipefail

# 引用公共调度库
# shellcheck source=service-notify.sh
source "/opt/backup/lib/service-notify.sh"

# --- 成功通知内容生成函数 ---
# 函数名必须是 "generate_success_notification" 以匹配公共库的推断
generate_success_notification() {
    local unit="$1"
    local hostname
    hostname="$(hostname -f 2>/dev/null || hostname)"
    local now
    now="$(date '+%Y-%m-%d %H:%M:%S %Z')"

    # 第1行: 标题
    echo "[成功] 服务 $unit 完成 @ $hostname"

    # 后续行: 正文
    cat <<EOF
服务名称: $unit
主机名称: $hostname
完成时间: $now

备份任务已成功完成。
EOF
}
# 导出函数
export -f generate_success_notification

# --- 主逻辑 ---
if [[ $# -ne 1 ]]; then
    echo "[SUCCESS] 用法: $0 <unit-name>" >&2
    exit 1
fi

# 调用公共调度器，参数大幅简化
process_event "$1" "SUCCESS"