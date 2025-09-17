#!/usr/bin/env bash
#
# /opt/backup/service-failure-notify.sh
# 内容生成器：为失败事件生成通知标题和正文。

set -euo pipefail

# 引用公共调度库
# shellcheck source=service-notify.sh
source "/opt/backup/scripts/service-notify.sh"

# --- 失败通知内容生成函数 ---
# 函数名必须是 "generate_failure_notification" 以匹配公共库的推断
generate_failure_notification() {
    local unit="$1"
    local hostname
    hostname="$(hostname -f 2>/dev/null || hostname)"
    local now
    now="$(date '+%Y-%m-%d %H:%M:%S %Z')"

    # 第1行: 标题
    echo "[告警] 服务 $unit 失败 @ $hostname"

    # 后续行: 正文
    cat <<EOF
服务名称: $unit
主机名称: $hostname
失败时间: $now

---------- 服务状态 ----------
$(systemctl status --full "$unit" 2>&1 || true)
EOF
}
# 将函数导出，以便子 shell 可以调用它
export -f generate_failure_notification

# --- 主逻辑 ---
if [[ $# -ne 1 ]]; then
    echo "[FAILURE] 用法: $0 <unit-name>" >&2
    exit 1
fi

# 调用公共调度器，参数大幅简化
process_event "$1" "FAILURE"