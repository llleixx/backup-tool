#!/usr/bin/env bash
#
# 备份执行脚本

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

source "${SCRIPT_DIR}/utils.sh"

if [[ -z "$1" ]]; then echo "错误：必须提供配置文件路径作为参数。" >&2; exit 1; fi
CONF_FILE="$1"
if [[ ! -f "$CONF_FILE" ]]; then echo "错误：配置文件 '${CONF_FILE}' 未找到。" >&2; exit 1; fi

check_dependency jq

CONFIG_ID=$(config_get_required "$CONF_FILE" "CONFIG_ID") || exit 1
BACKUP_FILES_LIST=$(config_get_required "$CONF_FILE" "BACKUP_FILES_LIST") || exit 1
RESTIC_REPOSITORY=$(config_get_required "$CONF_FILE" "RESTIC_REPOSITORY") || exit 1
RESTIC_PASSWORD=$(config_get_optional "$CONF_FILE" "RESTIC_PASSWORD" "")
KEEP_DAILY=$(config_get_required "$CONF_FILE" "KEEP_DAILY") || exit 1
KEEP_WEEKLY=$(config_get_required "$CONF_FILE" "KEEP_WEEKLY") || exit 1
GROUP_BY=$(config_get_optional "$CONF_FILE" "GROUP_BY" "tags")
PRE_BACKUP_HOOK=$(config_get_optional "$CONF_FILE" "PRE_BACKUP_HOOK" "")
POST_SUCCESS_HOOK=$(config_get_optional "$CONF_FILE" "POST_SUCCESS_HOOK" "")
POST_FAILURE_HOOK=$(config_get_optional "$CONF_FILE" "POST_FAILURE_HOOK" "")

export RESTIC_REPOSITORY RESTIC_PASSWORD

RESTIC_BIN=$(command -v restic)
if [[ -z "$RESTIC_BIN" ]]; then echo "错误： 'restic' 命令未找到。" >&2; exit 1; fi
RESTIC_OPTS=()
if [[ -z "$RESTIC_PASSWORD" ]]; then RESTIC_OPTS+=(--insecure-no-password); fi

# --- 构建备份命令 ---
BACKUP_CMD=("$RESTIC_BIN" "${RESTIC_OPTS[@]}" "backup" "--verbose" "--files-from" "${BACKUP_FILES_LIST}")
BACKUP_CMD+=("--tag" "${CONFIG_ID}")
BACKUP_CMD+=("--group-by" "${GROUP_BY}")

# --- 构建清理命令 ---
FORGET_CMD=("$RESTIC_BIN" "${RESTIC_OPTS[@]}" "forget" "--keep-daily" "${KEEP_DAILY}" "--keep-weekly" "${KEEP_WEEKLY}" "--prune")
FORGET_CMD+=("--group-by" "${GROUP_BY}")

run_hook() {
  local hook_name="$1"
  local hook_script="$2"
  local hook_status
  if [[ -z "$hook_script" ]]; then
    return 0
  fi
  if [[ ! -f "$hook_script" ]]; then
    echo "[$(date)] -- ${hook_name} hook 脚本不存在: ${hook_script}" >&2
    return 1
  fi
  echo "[$(date)] -- 执行 ${hook_name} hook: ${hook_script}"
  if bash "$hook_script"; then
    return 0
  else
    hook_status=$?
  fi
  echo "[$(date)] -- ${hook_name} hook 执行失败 (exit code ${hook_status})" >&2
  return "$hook_status"
}

echo "[$(date)] -- 开始备份 (Config: ${CONF_FILE})"
if ! run_hook "备份前" "${PRE_BACKUP_HOOK:-}"; then
  exit 21
fi

backup_status=0
if "${BACKUP_CMD[@]}"; then
  echo "[$(date)] -- 开始清理旧备份 (Config: ${CONF_FILE})"
  if "${FORGET_CMD[@]}"; then
    backup_status=0
  else
    backup_status=$?
  fi
else
  backup_status=$?
fi

if [[ $backup_status -ne 0 ]]; then
  echo "[$(date)] -- 备份失败 (Config: ${CONF_FILE})" >&2
  if ! run_hook "备份失败后" "${POST_FAILURE_HOOK:-}"; then
    echo "[$(date)] -- 备份失败后 hook 执行失败" >&2
    exit 23
  fi
  exit "$backup_status"
fi

if ! run_hook "备份成功后" "${POST_SUCCESS_HOOK:-}"; then
  exit 22
fi

echo "[$(date)] -- 备份完成 (Config: ${CONF_FILE})"
