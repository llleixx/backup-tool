#!/usr/bin/env bash
#
# 通用邮件发送脚本 (msmtp)
# 功能：从参数读取配置和标题，从标准输入读取正文，然后发送邮件。

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

source "${SCRIPT_DIR}/utils.sh"

# --- 参数检查 ---
if [[ $# -ne 2 ]]; then
    echo "用法: $0 <config-file-path> <subject>" >&2
    exit 1
fi

readonly CONF_FILE="$1"
readonly SUBJECT="$2"

if [[ ! -f "$CONF_FILE" ]]; then
    echo "错误: 邮件配置文件 '$CONF_FILE' 不存在。" >&2
    exit 1
fi

check_dependency jq

# --- 检查必要的配置是否存在 ---
SMTP_HOST=$(config_get_required "$CONF_FILE" "SMTP_HOST") || exit 1
SMTP_PORT=$(config_get_required "$CONF_FILE" "SMTP_PORT") || exit 1
SMTP_USER=$(config_get_required "$CONF_FILE" "SMTP_USER") || exit 1
SMTP_PASS=$(config_get_required "$CONF_FILE" "SMTP_PASS") || exit 1
FROM_ADDR=$(config_get_required "$CONF_FILE" "FROM_ADDR") || exit 1
TO_ADDR=$(config_get_required "$CONF_FILE" "TO_ADDR") || exit 1
SMTP_TLS=$(config_get_optional "$CONF_FILE" "SMTP_TLS" "starttls")

# --- 构建 msmtp 参数 ---
declare -a msmtp_opts
msmtp_opts+=(--host="$SMTP_HOST")
msmtp_opts+=(--port="$SMTP_PORT")
msmtp_opts+=(--user="$SMTP_USER")
export SMTP_PASS_FOR_MSMTP="$SMTP_PASS"
msmtp_opts+=(--passwordeval='printf %s "$SMTP_PASS_FOR_MSMTP"')
msmtp_opts+=(--from="$FROM_ADDR")
msmtp_opts+=(--auth="on")

case "${SMTP_TLS}" in
    on)       msmtp_opts+=(--tls=on --tls-starttls=off) ;;
    starttls) msmtp_opts+=(--tls=on --tls-starttls=on) ;;
    off)      msmtp_opts+=(--tls=off) ;;
    *)
      echo "警告: 未知的 SMTP_TLS 值，将默认使用 'starttls'。" >&2
      msmtp_opts+=(--tls=on --tls-starttls=on) ;;
esac

# --- 发送邮件 ---
# 使用子 shell 来组合所有输出，然后通过管道 `|` 一次性传给 msmtp
(
    cat <<EOF
From: ${FROM_ADDR}
To: ${TO_ADDR}
Subject: ${SUBJECT}
Date: $(LC_ALL=C date -R)
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: 8bit

EOF
    cat
) | msmtp "${msmtp_opts[@]}" -t

unset SMTP_PASS_FOR_MSMTP
