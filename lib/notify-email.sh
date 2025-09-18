#!/usr/bin/env bash
#
# 通用邮件发送脚本 (msmtp)
# 功能：从参数读取配置和标题，从标准输入读取正文，然后发送邮件。

set -euo pipefail

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

# --- 从配置文件加载变量 ---
# shellcheck source=/dev/null
source "$CONF_FILE"

# --- 检查必要的配置是否存在 ---
: "${SMTP_HOST?SMTP_HOST 未在配置文件中设置}"
: "${SMTP_PORT?SMTP_PORT 未在配置文件中设置}"
: "${SMTP_USER?SMTP_USER 未在配置文件中设置}"
: "${SMTP_PASS?SMTP_PASS 未在配置文件中设置}"
: "${FROM_ADDR?FROM_ADDR 未在配置文件中设置}"
: "${TO_ADDR?TO_ADDR 未在配置文件中设置}"

# --- 从标准输入读取邮件正文 ---
BODY_CONTENT=$(cat)
readonly BODY_CONTENT

if [[ -z "$BODY_CONTENT" ]]; then
    echo "警告: 邮件正文为空。" >&2
fi

# --- 构造完整的邮件内容 (包含MIME头) ---
MAIL_CONTENT=$(cat <<EOF
From: ${FROM_ADDR}
To: ${TO_ADDR}
Subject: ${SUBJECT}
Date: $(LC_ALL=C date -R)
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: 8bit

${BODY_CONTENT}
EOF
)
readonly MAIL_CONTENT

# --- 构建 msmtp 参数 ---
declare -a msmtp_opts
msmtp_opts+=(--host="$SMTP_HOST")
msmtp_opts+=(--port="$SMTP_PORT")
msmtp_opts+=(--user="$SMTP_USER")
msmtp_opts+=(--passwordeval="echo '${SMTP_PASS}'")
msmtp_opts+=(--from="$FROM_ADDR")
msmtp_opts+=(--auth="on")

case "${SMTP_TLS:-starttls}" in
    on)       msmtp_opts+=(--tls=on --tls-starttls=off) ;;
    starttls) msmtp_opts+=(--tls=on --tls-starttls=on) ;;
    off)      msmtp_opts+=(--tls=off) ;;
    *)
      echo "警告: 未知的 SMTP_TLS 值，将默认使用 'starttls'。" >&2
      msmtp_opts+=(--tls=on --tls-starttls=on) ;;
esac

# --- 发送邮件 ---
echo "$MAIL_CONTENT" | msmtp "${msmtp_opts[@]}" -t