#!/usr/bin/env bash
#
# /opt/backup/lib/notify-telegram.sh
#
# 通用 Telegram Bot 发送脚本 (v2 - 纯文本版)
# 功能：从参数读取配置和标题，从标准输入读取正文，然后通过 Bot API 发送纯文本消息。

set -euo pipefail

# --- 依赖检查 ---
if ! command -v curl &>/dev/null; then
    echo "[TELEGRAM] 错误: 'curl' 命令未找到，请先安装它。" >&2
    exit 1
fi
if ! command -v jq &>/dev/null; then
    echo "[TELEGRAM] 错误: 'jq' 命令未找到，请先安装它。" >&2
    exit 1
fi

# --- 参数检查 ---
if [[ $# -ne 2 ]]; then
    echo "[TELEGRAM] 用法: $0 <config-file-path> <subject>" >&2
    exit 1
fi

readonly CONF_FILE="$1"
readonly SUBJECT="$2"

if [[ ! -f "$CONF_FILE" ]]; then
    echo "[TELEGRAM] 错误: Telegram 配置文件 '$CONF_FILE' 不存在。" >&2
    exit 1
fi

# --- 从标准输入读取消息正文 ---
readonly BODY_CONTENT
BODY_CONTENT=$(cat)

if [[ -z "$BODY_CONTENT" ]]; then
    echo "[TELEGRAM] 警告: 消息正文为空。" >&2
fi

# --- 从配置文件加载变量 ---
# shellcheck source=/dev/null
source "$CONF_FILE"

# --- 检查必要的配置是否存在 ---
: "${TELEGRAM_BOT_TOKEN?TELEGRAM_BOT_TOKEN 未在配置文件中设置}"
: "${TELEGRAM_CHAT_ID?TELEGRAM_CHAT_ID 未在配置文件中设置}"

# --- 组合纯文本消息 ---
# 将标题和正文简单地组合在一起，用换行符分隔。
readonly message_text="${SUBJECT}

${BODY_CONTENT}"

# --- 构建 JSON payload ---
# 不再需要 "parse_mode"，Telegram 默认使用纯文本。
readonly payload=$(jq -nc \
  --arg chat_id "$TELEGRAM_CHAT_ID" \
  --arg text "$message_text" \
  '{"chat_id": $chat_id, "text": $text}')

# --- 发送请求 ---
# [修正] 修正了 sendMessage 前的斜杠
readonly api_url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"

# 使用 curl 发送请求，-s 静默模式，-S 在出错时显示错误
response=$(curl -fsSL -X POST \
  -H "Content-Type: application/json" \
  -d "$payload" \
  "$api_url")

# --- 检查 API 响应 ---
# 使用 jq 检查响应中的 "ok" 字段是否为 true
if [[ $(echo "$response" | jq -r '.ok') == "true" ]]; then
  echo "[TELEGRAM] 消息已成功发送至 Chat ID: ${TELEGRAM_CHAT_ID}" >&2
else
  echo "[TELEGRAM] 错误: 发送消息失败。API 响应:" >&2
  echo "$response" >&2
  exit 1
fi