#!/usr/bin/env bash

set -euo pipefail
if [[ -z "$1" ]]; then echo "错误：必须提供配置文件路径作为参数。" >&2; exit 1; fi
CONF_FILE="$1"
if [[ ! -f "$CONF_FILE" ]]; then echo "错误：配置文件 '${CONF_FILE}' 未找到。" >&2; exit 1; fi
set -a; source "$CONF_FILE"; set +a
RESTIC_BIN=$(command -v restic)
if [[ -z "$RESTIC_BIN" ]]; then echo "错误： 'restic' 命令未找到。" >&2; exit 1; fi
RESTIC_OPTS=""
if [[ -z "$RESTIC_PASSWORD" ]]; then RESTIC_OPTS="--insecure-no-password"; fi
echo "[\$(date)] -- 开始备份 (Config: ${CONF_FILE})"
$RESTIC_BIN $RESTIC_OPTS backup --verbose --files-from "${BACKUP_FILES_LIST}"
echo "[\$(date)] -- 开始清理旧备份 (Config: ${CONF_FILE})"
$RESTIC_BIN $RESTIC_OPTS forget --keep-daily "${KEEP_DAILY}" --keep-weekly "${KEEP_WEEKLY}" --prune
echo "[\$(date)] -- 备份完成 (Config: ${CONF_FILE})"