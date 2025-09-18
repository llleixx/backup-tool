#!/usr/bin/env bash
#
# 常用变量和路径配置

readonly REPO="llleixx/backup-tool"
readonly VERSION="v0.0.1"

# --- 目录和文件配置 ---
readonly ROOT_DIR="/opt/backup"
readonly CONF_DIR="$ROOT_DIR/conf"
readonly SCRIPT_DIR="$ROOT_DIR/lib"
readonly DEFAULT_BACKUP_LIST="$ROOT_DIR/backup_list.txt"
readonly SYSTEMD_DIR="/etc/systemd/system"
readonly MIN_RESTIC_VERSION="0.17.0"

# --- 颜色定义 ---
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_NC='\033[0m' # No Color