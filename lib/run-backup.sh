#!/usr/bin/env bash
#
# 备份执行脚本

set -euo pipefail
if [[ -z "$1" ]]; then echo "错误：必须提供配置文件路径作为参数。" >&2; exit 1; fi
CONF_FILE="$1"
if [[ ! -f "$CONF_FILE" ]]; then echo "错误：配置文件 '${CONF_FILE}' 未找到。" >&2; exit 1; fi
set -a; 
# shellcheck source=/dev/null
source "$CONF_FILE";
set +a
RESTIC_BIN=$(command -v restic)
if [[ -z "$RESTIC_BIN" ]]; then echo "错误： 'restic' 命令未找到。" >&2; exit 1; fi
RESTIC_OPTS=""
if [[ -z "$RESTIC_PASSWORD" ]]; then RESTIC_OPTS="--insecure-no-password"; fi

# 如果配置文件中未定义 GROUP_BY，则默认为 'tags'
GROUP_BY=${GROUP_BY:-tags}

# --- 构建备份命令 ---
BACKUP_CMD=("$RESTIC_BIN" $RESTIC_OPTS "backup" "--verbose" "--files-from" "${BACKUP_FILES_LIST}")
BACKUP_CMD+=("--tag" "${CONFIG_ID}")
BACKUP_CMD+=("--group-by" "${GROUP_BY}")

# --- 构建清理命令 ---
FORGET_CMD=("$RESTIC_BIN" $RESTIC_OPTS "forget" "--keep-daily" "${KEEP_DAILY}" "--keep-weekly" "${KEEP_WEEKLY}" "--prune")
FORGET_CMD+=("--group-by" "${GROUP_BY}")

run_hook() {
  local hook_name="$1"
  local hook_script="$2"
  if [[ -z "$hook_script" ]]; then
    return 0
  fi
  if [[ ! -f "$hook_script" ]]; then
    echo "[$(date)] -- ${hook_name} hook 脚本不存在: ${hook_script}" >&2
    return 1
  fi
  echo "[$(date)] -- 执行 ${hook_name} hook: ${hook_script}"
  local hook_status
  set +e
  bash "$hook_script"
  hook_status=$?
  set -e
  if [[ $hook_status -ne 0 ]]; then
    echo "[$(date)] -- ${hook_name} hook 执行失败 (exit code ${hook_status})" >&2
    return "$hook_status"
  fi
}

echo "[$(date)] -- 开始备份 (Config: ${CONF_FILE})"
if ! run_hook "备份前" "${PRE_BACKUP_HOOK:-}"; then
  exit 1
fi

backup_status=0
set +e
"${BACKUP_CMD[@]}"
backup_status=$?
if [[ $backup_status -eq 0 ]]; then
  echo "[$(date)] -- 开始清理旧备份 (Config: ${CONF_FILE})"
  "${FORGET_CMD[@]}"
  backup_status=$?
fi
set -e

if [[ $backup_status -ne 0 ]]; then
  echo "[$(date)] -- 备份失败 (Config: ${CONF_FILE})" >&2
  if ! run_hook "备份失败后" "${POST_FAILURE_HOOK:-}"; then
    echo "[$(date)] -- 备份失败后 hook 执行失败" >&2
  fi
  exit "$backup_status"
fi

if ! run_hook "备份成功后" "${POST_SUCCESS_HOOK:-}"; then
  exit 1
fi

echo "[$(date)] -- 备份完成 (Config: ${CONF_FILE})"
