#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# Sub-Store 前后端源码安装脚本，适用于 systemd Linux 服务器。
# 官方仓库：
#   后端：https://github.com/sub-store-org/Sub-Store
#   前端：https://github.com/sub-store-org/Sub-Store-Front-End

BACKEND_REPO="https://github.com/sub-store-org/Sub-Store.git"
FRONTEND_REPO="https://github.com/sub-store-org/Sub-Store-Front-End.git"

INSTALL_DIR="/opt/sub-store"
DATA_DIR="/opt/sub-store/data"
CONFIG_DIR="/etc/sub-store"
SERVICE_NAME="sub-store"
SERVICE_USER="substore"
INSTALLER_BIN="/usr/local/bin/sub-store-installer"

BACKEND_BRANCH="master"
FRONTEND_BRANCH="master"
LISTEN_HOST="0.0.0.0"
BACKEND_PORT="3000"
API_URL=""
CORS_ALLOWED_ORIGINS="*"
FRONTEND_BACKEND_PATH=""
FRONTEND_BACKEND_PATH_EXPLICIT=0

NODE_MAJOR="22"
PNPM_VERSION="11.0.9"
NODE_BIN=""

BACKUP_UPLOAD_CRON="0 */6 * * *"
BACKUP_DOWNLOAD_CRON=""
LOCAL_BACKUP_DIR="/opt/sub-store/backups"
LOCAL_BACKUP_KEEP="7"
LOCAL_BACKUP_CRON="daily"
BACKUP_FILE=""
BACKUP_REASON="manual"
UPDATE_BACKUP=1
WEBDAV_URL=""
WEBDAV_USERNAME=""
WEBDAV_PASSWORD=""
WEBDAV_PATH="/sub-store"
WEBDAV_KEEP="7"
BACKEND_SYNC_CRON=""
PRODUCE_CRON=""
DATA_URL=""
DATA_URL_POST=""
BACKEND_DEFAULT_PROXY=""
PUSH_SERVICE=""

INTERACTIVE=1
ASSUME_YES=0
SKIP_DEPS=0
START_SERVICE=1
SHOW_SECRETS=0
ACTION=""
ORIGINAL_SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
case "$ORIGINAL_SCRIPT_PATH" in
  /*)
    ;;
  *)
    ORIGINAL_SCRIPT_PATH="$(pwd)/${ORIGINAL_SCRIPT_PATH}"
    ;;
esac

declare -a EXTRA_ENV_PAIRS=()
declare -A CLI_OVERRIDES=()

set_cli_override() {
  local key="$1"
  local value="$2"
  CLI_OVERRIDES["$key"]="$value"
}

apply_cli_overrides() {
  local key

  for key in "${!CLI_OVERRIDES[@]}"; do
    printf -v "$key" '%s' "${CLI_OVERRIDES[$key]}"
  done

  if [[ "${CLI_OVERRIDES[FRONTEND_BACKEND_PATH]+set}" == "set" ]]; then
    FRONTEND_BACKEND_PATH_EXPLICIT=1
  fi
}

usage() {
  cat <<'EOF'
用法：
  bash install_sub_store.sh [操作] [选项]

操作：
  install / 安装            全新安装 Sub-Store
  update / 更新             更新已安装的 Sub-Store，保留配置和数据
  backup / 备份             立即创建本地数据备份
  backup-config / 备份配置   只修改自动备份、WebDAV 和官方备份 cron
  restore / 恢复            从本地备份恢复数据和配置
  list-backups / 查看备份   查看本地备份列表
  cleanup-backups / 清理备份 清理旧备份，只保留指定数量
  webdav-test / 测试 WebDAV 测试 WebDAV 远程备份连接
  uninstall / 卸载          卸载 Sub-Store
  config / 修改配置         修改环境配置并重启服务
  show / 查看配置           查看服务状态和当前配置
  status / 显示状态         只显示 systemd 服务状态
  start / 启动              启动服务并设置开机自启
  restart / 重启            重启服务
  stop / 停止               停止服务，不影响开机自启
  disable / 关闭            停止服务并禁用开机自启

不传操作时，交互模式会显示菜单；非交互模式默认执行 install。

核心选项：
  --listen HOST                 后端监听地址。默认：0.0.0.0
  --port PORT                   后端监听端口。默认：3000
  --api-url URL                 写入前端的后端访问地址，也就是 VITE_API_URL
  --install-dir DIR             安装目录。默认：/opt/sub-store
  --data-dir DIR                Sub-Store 数据目录。默认：/opt/sub-store/data
  --service-name NAME           systemd 服务名。默认：sub-store
  --cors ORIGINS                CORS 允许来源，即 SUB_STORE_CORS_ALLOWED_ORIGINS。默认：*

Sub-Store 官方运行选项：
  --backup-upload-cron CRON     自动上传备份 cron，即 SUB_STORE_BACKEND_UPLOAD_CRON。默认："0 */6 * * *"
  --backup-download-cron CRON   自动下载恢复 cron，即 SUB_STORE_BACKEND_DOWNLOAD_CRON。默认关闭
  --no-backup                   关闭默认自动上传备份
  --sync-cron CRON              订阅同步 cron，即 SUB_STORE_BACKEND_SYNC_CRON
  --produce-cron CRON           产物生成 cron，即 SUB_STORE_PRODUCE_CRON，例如："0 */2 * * *,sub,a"
  --restore-data-url URL        启动时从 URL 恢复数据，即 SUB_STORE_DATA_URL
  --restore-data-url-post JS    恢复后的官方后处理脚本，即 SUB_STORE_DATA_URL_POST
  --default-proxy VALUE         默认代理，即 SUB_STORE_BACKEND_DEFAULT_PROXY
  --push-service VALUE          推送服务，即 SUB_STORE_PUSH_SERVICE
  --frontend-backend-path PATH  前端访问后端的路径前缀，即 SUB_STORE_FRONTEND_BACKEND_PATH。默认随机生成
  --env KEY=VALUE               追加一个 SUB_STORE_* 环境变量，可重复传入

本地备份选项：
  --backup-dir DIR              本地备份目录。默认：/opt/sub-store/backups
  --backup-keep N               自动清理时保留最近 N 份备份。默认：7
  --local-backup-cron VALUE     本地自动备份时间，使用 systemd OnCalendar。默认：daily；可填 off 关闭
  --no-local-backup             关闭脚本本地自动备份 timer
  --backup-file FILE            恢复时指定备份文件
  --no-update-backup            更新已安装版本前不自动备份
  --webdav-url URL              WebDAV 服务地址，例如：https://example.com/dav
  --webdav-user USER            WebDAV 用户名
  --webdav-password PASSWORD    WebDAV 密码或应用密码
  --webdav-path PATH            WebDAV 远程目录。默认：/sub-store
  --webdav-keep N               WebDAV 远程保留最近 N 份备份。默认：7
  --no-webdav                   关闭 WebDAV 远程备份

构建和依赖选项：
  --backend-branch BRANCH       后端分支。默认：master
  --frontend-branch BRANCH      前端分支。默认：master
  --node-major MAJOR            需要安装的 NodeSource 主版本。默认：22
  --pnpm-version VERSION        通过 corepack 启用的 pnpm 版本。默认：11.0.9
  --skip-deps                   跳过系统依赖和 Node.js 安装
  --no-start                    只写入服务，不启用也不启动 systemd 服务
  --show-secrets                查看配置时显示未脱敏的敏感值
  -y, --yes                     自动确认安装
  --non-interactive             非交互模式，使用默认值和命令行参数
  -h, --help                    显示本帮助

示例：
  bash install_sub_store.sh
  bash install_sub_store.sh install --listen 0.0.0.0 --port 3000 --api-url /my-secret-path
  bash install_sub_store.sh update
  bash install_sub_store.sh backup-config
  bash install_sub_store.sh backup
  bash install_sub_store.sh webdav-test
  bash install_sub_store.sh restore --backup-file /opt/sub-store/backups/sub-store-manual-20260605-120000.tar.gz
  bash install_sub_store.sh --listen 0.0.0.0 --port 3000 --api-url http://example.com:3000/backend
  bash install_sub_store.sh --api-url https://sub.example.com/backend --cors https://sub.example.com
  bash install_sub_store.sh --no-backup --env SUB_STORE_MAX_HEADER_SIZE=65536
  bash install_sub_store.sh uninstall
  bash install_sub_store.sh config
  bash install_sub_store.sh backup-config
  bash install_sub_store.sh show
  bash install_sub_store.sh status
  bash install_sub_store.sh start
  bash install_sub_store.sh restart
  bash install_sub_store.sh stop
  bash install_sub_store.sh disable

说明：
  官方 Gist 备份需要先在 Sub-Store 前端设置里配置 GitHub Token。
  自动上传/下载 cron 只负责调度官方后端备份动作，不会替你写入 GitHub Token。
EOF
}

log() {
  printf '\033[1;32m[信息]\033[0m %s\n' "$*"
}

warn() {
  printf '\033[1;33m[警告]\033[0m %s\n' "$*" >&2
}

die() {
  printf '\033[1;31m[错误]\033[0m %s\n' "$*" >&2
  exit 1
}

section() {
  printf '\n\033[1;36m==> %s\033[0m\n' "$*"
}

menu_option() {
  local number="$1"
  local title="$2"
  printf '  \033[1m[%s] %s\033[0m\n' "$number" "$title"
}

menu_note() {
  printf '      \033[2m说明：%s\033[0m\n' "$*"
}

read_interactive() {
  local prompt="$1"
  local __var_name="$2"
  local input=""

  if { : </dev/tty; } 2>/dev/null; then
    read -e -r -p "$prompt" input </dev/tty || input=""
  else
    die "当前没有可用的交互终端；请使用 --non-interactive 并在命令行传入必要参数"
  fi

  printf -v "$__var_name" '%s' "$input"
}

confirm() {
  local prompt="$1"
  local default="${2:-n}"
  local answer

  if [[ "$ASSUME_YES" -eq 1 ]]; then
    return 0
  fi

  if [[ "$INTERACTIVE" -eq 0 ]]; then
    [[ "$default" =~ ^[Yy]$ ]]
    return
  fi

  if [[ "$default" =~ ^[Yy]$ ]]; then
    read_interactive "${prompt} [Y/n]: " answer
    [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]
  else
    read_interactive "${prompt} [y/N]: " answer
    [[ "$answer" =~ ^[Yy]$ ]]
  fi
}

prompt_default() {
  local prompt="$1"
  local current="$2"
  local answer

  if [[ "$INTERACTIVE" -eq 0 ]]; then
    printf '%s' "$current"
    return
  fi

  read_interactive "${prompt} [${current}]: " answer
  printf '%s' "${answer:-$current}"
}

prompt_secret_default() {
  local prompt="$1"
  local current="$2"
  local answer suffix

  if [[ "$INTERACTIVE" -eq 0 ]]; then
    printf '%s' "$current"
    return
  fi

  if [[ -n "$current" ]]; then
    suffix="[已设置，直接回车保持不变]"
  else
    suffix="[未设置]"
  fi

  if { : </dev/tty; } 2>/dev/null; then
    read -s -r -p "${prompt} ${suffix}: " answer </dev/tty || answer=""
    printf '\n' >/dev/tty
  else
    die "当前没有可用的交互终端；请使用 --non-interactive 并在命令行传入必要参数"
  fi

  printf '%s' "${answer:-$current}"
}

choose_install_menu() {
  local choice

  section "安装与更新"
  menu_option 1 "安装 Sub-Store"
  menu_note "全新源码部署，写入环境文件和 systemd 服务"
  menu_option 2 "更新已安装版本"
  menu_note "保留配置和数据，更新源码并重新构建"
  menu_option 0 "返回主菜单"
  read_interactive "请选择 [1]: " choice
  case "${choice:-1}" in
    1) ACTION="install" ;;
    2) ACTION="update" ;;
    0) return 1 ;;
    *) die "无效选择：${choice}" ;;
  esac
}

choose_config_menu() {
  local choice

  section "配置与查看"
  menu_option 1 "修改配置"
  menu_note "修改监听、路径、备份等配置，并按需重建前端"
  menu_option 2 "查看配置"
  menu_note "默认隐藏后端路径、Token、密码等敏感值"
  menu_option 3 "只修改备份配置"
  menu_note "不询问监听地址、端口、后端路径"
  menu_option 0 "返回主菜单"
  read_interactive "请选择 [1]: " choice
  case "${choice:-1}" in
    1) ACTION="config" ;;
    2) ACTION="show" ;;
    3) ACTION="backup-config" ;;
    0) return 1 ;;
    *) die "无效选择：${choice}" ;;
  esac
}

choose_backup_menu() {
  local choice

  section "备份与恢复"
  menu_option 1 "立即备份"
  menu_note "创建本地 tar.gz；已配置 WebDAV 时会同步上传"
  menu_option 2 "从本地备份恢复"
  menu_note "恢复前会先创建 pre-restore 当前状态备份"
  menu_option 3 "查看本地备份"
  menu_option 4 "清理旧备份"
  menu_option 5 "测试 WebDAV 远程备份"
  menu_option 6 "修改备份配置"
  menu_note "只修改本地自动备份、WebDAV、官方备份 cron"
  menu_option 0 "返回主菜单"
  read_interactive "请选择 [1]: " choice
  case "${choice:-1}" in
    1) ACTION="backup" ;;
    2) ACTION="restore" ;;
    3) ACTION="list-backups" ;;
    4) ACTION="cleanup-backups" ;;
    5) ACTION="webdav-test" ;;
    6) ACTION="backup-config" ;;
    0) return 1 ;;
    *) die "无效选择：${choice}" ;;
  esac
}

choose_service_menu() {
  local choice

  section "服务控制"
  menu_option 1 "显示状态"
  menu_option 2 "启动服务"
  menu_option 3 "重启服务"
  menu_option 4 "停止服务"
  menu_option 5 "关闭服务（停止并禁用开机自启）"
  menu_option 0 "返回主菜单"
  read_interactive "请选择 [1]: " choice
  case "${choice:-1}" in
    1) ACTION="status" ;;
    2) ACTION="start" ;;
    3) ACTION="restart" ;;
    4) ACTION="stop" ;;
    5) ACTION="disable" ;;
    0) return 1 ;;
    *) die "无效选择：${choice}" ;;
  esac
}

choose_action() {
  local choice

  [[ -z "$ACTION" ]] || return 0

  if [[ "$INTERACTIVE" -eq 0 ]]; then
    ACTION="install"
    return
  fi

  while true; do
    section "选择要执行的操作"
    menu_option 1 "安装与更新"
    menu_option 2 "配置与查看"
    menu_option 3 "备份与恢复"
    menu_option 4 "服务控制"
    menu_option 5 "卸载 Sub-Store"
    menu_option 0 "退出"

    read_interactive "请选择 [1]: " choice
    case "${choice:-1}" in
      1) choose_install_menu && return 0 ;;
      2) choose_config_menu && return 0 ;;
      3) choose_backup_menu && return 0 ;;
      4) choose_service_menu && return 0 ;;
      5) ACTION="uninstall"; return 0 ;;
      0) ACTION="exit"; return 0 ;;
      *) die "无效选择：${choice}" ;;
    esac
  done
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      install|安装)
        ACTION="install"
        shift
        ;;
      update|更新|upgrade|已安装更新)
        ACTION="update"
        shift
        ;;
      backup|备份)
        ACTION="backup"
        shift
        ;;
      backup-config|backup-configure|备份配置|自动备份配置)
        ACTION="backup-config"
        shift
        ;;
      restore|恢复)
        ACTION="restore"
        shift
        ;;
      list-backups|backups|查看备份)
        ACTION="list-backups"
        shift
        ;;
      cleanup-backups|clean-backups|清理备份)
        ACTION="cleanup-backups"
        shift
        ;;
      webdav-test|webdev-test|测试WebDAV|测试webdav)
        ACTION="webdav-test"
        shift
        ;;
      uninstall|卸载)
        ACTION="uninstall"
        shift
        ;;
      config|修改配置|configure)
        ACTION="config"
        shift
        ;;
      show|查看配置)
        ACTION="show"
        shift
        ;;
      status|状态|显示状态)
        ACTION="status"
        shift
        ;;
      start|启动)
        ACTION="start"
        shift
        ;;
      restart|重启)
        ACTION="restart"
        shift
        ;;
      stop|停止)
        ACTION="stop"
        shift
        ;;
      disable|关闭)
        ACTION="disable"
        shift
        ;;
      --listen)
        LISTEN_HOST="${2:?选项 --listen 缺少参数}"
        set_cli_override "LISTEN_HOST" "$LISTEN_HOST"
        shift 2
        ;;
      --port)
        BACKEND_PORT="${2:?选项 --port 缺少参数}"
        set_cli_override "BACKEND_PORT" "$BACKEND_PORT"
        shift 2
        ;;
      --api-url)
        API_URL="${2:?选项 --api-url 缺少参数}"
        set_cli_override "API_URL" "$API_URL"
        shift 2
        ;;
      --install-dir)
        INSTALL_DIR="${2:?选项 --install-dir 缺少参数}"
        set_cli_override "INSTALL_DIR" "$INSTALL_DIR"
        shift 2
        ;;
      --data-dir)
        DATA_DIR="${2:?选项 --data-dir 缺少参数}"
        set_cli_override "DATA_DIR" "$DATA_DIR"
        shift 2
        ;;
      --service-name)
        SERVICE_NAME="${2:?选项 --service-name 缺少参数}"
        set_cli_override "SERVICE_NAME" "$SERVICE_NAME"
        shift 2
        ;;
      --cors)
        CORS_ALLOWED_ORIGINS="${2:?选项 --cors 缺少参数}"
        set_cli_override "CORS_ALLOWED_ORIGINS" "$CORS_ALLOWED_ORIGINS"
        shift 2
        ;;
      --backup-upload-cron)
        BACKUP_UPLOAD_CRON="${2:?选项 --backup-upload-cron 缺少参数}"
        set_cli_override "BACKUP_UPLOAD_CRON" "$BACKUP_UPLOAD_CRON"
        shift 2
        ;;
      --backup-download-cron)
        BACKUP_DOWNLOAD_CRON="${2:?选项 --backup-download-cron 缺少参数}"
        set_cli_override "BACKUP_DOWNLOAD_CRON" "$BACKUP_DOWNLOAD_CRON"
        shift 2
        ;;
      --no-backup)
        BACKUP_UPLOAD_CRON=""
        set_cli_override "BACKUP_UPLOAD_CRON" "$BACKUP_UPLOAD_CRON"
        shift
        ;;
      --backup-dir)
        LOCAL_BACKUP_DIR="${2:?选项 --backup-dir 缺少参数}"
        set_cli_override "LOCAL_BACKUP_DIR" "$LOCAL_BACKUP_DIR"
        shift 2
        ;;
      --backup-keep)
        LOCAL_BACKUP_KEEP="${2:?选项 --backup-keep 缺少参数}"
        set_cli_override "LOCAL_BACKUP_KEEP" "$LOCAL_BACKUP_KEEP"
        shift 2
        ;;
      --local-backup-cron)
        LOCAL_BACKUP_CRON="${2:?选项 --local-backup-cron 缺少参数}"
        set_cli_override "LOCAL_BACKUP_CRON" "$LOCAL_BACKUP_CRON"
        shift 2
        ;;
      --no-local-backup)
        LOCAL_BACKUP_CRON="off"
        set_cli_override "LOCAL_BACKUP_CRON" "$LOCAL_BACKUP_CRON"
        shift
        ;;
      --backup-file)
        BACKUP_FILE="${2:?选项 --backup-file 缺少参数}"
        shift 2
        ;;
      --backup-reason)
        BACKUP_REASON="${2:?选项 --backup-reason 缺少参数}"
        shift 2
        ;;
      --no-update-backup)
        UPDATE_BACKUP=0
        shift
        ;;
      --webdav-url)
        WEBDAV_URL="${2:?选项 --webdav-url 缺少参数}"
        set_cli_override "WEBDAV_URL" "$WEBDAV_URL"
        shift 2
        ;;
      --webdav-user|--webdav-username)
        WEBDAV_USERNAME="${2:?选项 --webdav-user 缺少参数}"
        set_cli_override "WEBDAV_USERNAME" "$WEBDAV_USERNAME"
        shift 2
        ;;
      --webdav-password)
        WEBDAV_PASSWORD="${2:?选项 --webdav-password 缺少参数}"
        set_cli_override "WEBDAV_PASSWORD" "$WEBDAV_PASSWORD"
        shift 2
        ;;
      --webdav-path)
        WEBDAV_PATH="${2:?选项 --webdav-path 缺少参数}"
        set_cli_override "WEBDAV_PATH" "$WEBDAV_PATH"
        shift 2
        ;;
      --webdav-keep)
        WEBDAV_KEEP="${2:?选项 --webdav-keep 缺少参数}"
        set_cli_override "WEBDAV_KEEP" "$WEBDAV_KEEP"
        shift 2
        ;;
      --no-webdav)
        WEBDAV_URL=""
        WEBDAV_USERNAME=""
        WEBDAV_PASSWORD=""
        set_cli_override "WEBDAV_URL" "$WEBDAV_URL"
        set_cli_override "WEBDAV_USERNAME" "$WEBDAV_USERNAME"
        set_cli_override "WEBDAV_PASSWORD" "$WEBDAV_PASSWORD"
        shift
        ;;
      --sync-cron)
        BACKEND_SYNC_CRON="${2:?选项 --sync-cron 缺少参数}"
        set_cli_override "BACKEND_SYNC_CRON" "$BACKEND_SYNC_CRON"
        shift 2
        ;;
      --produce-cron)
        PRODUCE_CRON="${2:?选项 --produce-cron 缺少参数}"
        set_cli_override "PRODUCE_CRON" "$PRODUCE_CRON"
        shift 2
        ;;
      --restore-data-url)
        DATA_URL="${2:?选项 --restore-data-url 缺少参数}"
        set_cli_override "DATA_URL" "$DATA_URL"
        shift 2
        ;;
      --restore-data-url-post)
        DATA_URL_POST="${2:?选项 --restore-data-url-post 缺少参数}"
        set_cli_override "DATA_URL_POST" "$DATA_URL_POST"
        shift 2
        ;;
      --default-proxy)
        BACKEND_DEFAULT_PROXY="${2:?选项 --default-proxy 缺少参数}"
        set_cli_override "BACKEND_DEFAULT_PROXY" "$BACKEND_DEFAULT_PROXY"
        shift 2
        ;;
      --push-service)
        PUSH_SERVICE="${2:?选项 --push-service 缺少参数}"
        set_cli_override "PUSH_SERVICE" "$PUSH_SERVICE"
        shift 2
        ;;
      --frontend-backend-path)
        FRONTEND_BACKEND_PATH="${2:?选项 --frontend-backend-path 缺少参数}"
        FRONTEND_BACKEND_PATH_EXPLICIT=1
        set_cli_override "FRONTEND_BACKEND_PATH" "$FRONTEND_BACKEND_PATH"
        shift 2
        ;;
      --env)
        EXTRA_ENV_PAIRS+=("${2:?选项 --env 缺少参数}")
        shift 2
        ;;
      --backend-branch)
        BACKEND_BRANCH="${2:?选项 --backend-branch 缺少参数}"
        shift 2
        ;;
      --frontend-branch)
        FRONTEND_BRANCH="${2:?选项 --frontend-branch 缺少参数}"
        shift 2
        ;;
      --node-major)
        NODE_MAJOR="${2:?选项 --node-major 缺少参数}"
        shift 2
        ;;
      --pnpm-version)
        PNPM_VERSION="${2:?选项 --pnpm-version 缺少参数}"
        shift 2
        ;;
      --skip-deps)
        SKIP_DEPS=1
        shift
        ;;
      --no-start)
        START_SERVICE=0
        shift
        ;;
      --show-secrets)
        SHOW_SECRETS=1
        shift
        ;;
      --non-interactive)
        INTERACTIVE=0
        shift
        ;;
      -y|--yes)
        ASSUME_YES=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "未知选项：$1"
        ;;
    esac
  done
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "请使用 root 权限运行，例如：sudo bash install_sub_store.sh"
}

require_systemd() {
  command -v systemctl >/dev/null 2>&1 || die "未找到 systemctl；本脚本只适用于 systemd 系统"
}

detect_package_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    printf 'apt'
  elif command -v dnf >/dev/null 2>&1; then
    printf 'dnf'
  elif command -v yum >/dev/null 2>&1; then
    printf 'yum'
  elif command -v pacman >/dev/null 2>&1; then
    printf 'pacman'
  else
    printf 'unknown'
  fi
}

install_base_dependencies() {
  [[ "$SKIP_DEPS" -eq 1 ]] && return

  local pm
  pm="$(detect_package_manager)"
  log "使用 ${pm} 安装基础依赖：curl、git、编译工具"

  case "$pm" in
    apt)
      apt-get update
      apt-get install -y ca-certificates curl git build-essential
      ;;
    dnf)
      dnf install -y ca-certificates curl git gcc-c++ make
      ;;
    yum)
      yum install -y ca-certificates curl git gcc-c++ make
      ;;
    pacman)
      pacman -Sy --noconfirm ca-certificates curl git base-devel
      ;;
    *)
      die "暂不支持当前包管理器；请手动安装 curl、git、编译工具和 Node.js >= 20.18，或使用 --skip-deps 跳过依赖安装"
      ;;
  esac
}

node_bin_satisfies() {
  local node_bin="$1"
  local version major minor

  [[ -n "$node_bin" && -x "$node_bin" ]] || return 1
  version="$("$node_bin" -v | sed 's/^v//')"
  major="${version%%.*}"
  minor="${version#*.}"
  minor="${minor%%.*}"

  [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]] || return 1

  if (( major > 20 )); then
    return 0
  fi
  if (( major == 20 && minor >= 18 )); then
    return 0
  fi
  return 1
}

resolve_node_bin() {
  local candidate

  for candidate in /usr/bin/node /usr/local/bin/node "$(command -v node 2>/dev/null || true)"; do
    [[ -n "$candidate" ]] || continue
    node_bin_satisfies "$candidate" || continue
    printf '%s' "$candidate"
    return 0
  done

  return 1
}

node_bin_is_private_root_path() {
  local node_bin="$1"

  case "$node_bin" in
    /root/*)
      return 0
      ;;
  esac
  return 1
}

install_node_if_needed() {
  local current_node
  current_node="$(command -v node 2>/dev/null || true)"

  if node_bin_satisfies "$current_node" && ! node_bin_is_private_root_path "$current_node"; then
    NODE_BIN="$current_node"
    log "已检测到可用的 Node.js：$("$NODE_BIN" -v)（${NODE_BIN}）"
    return
  fi

  if node_bin_satisfies "$current_node" && node_bin_is_private_root_path "$current_node"; then
    warn "检测到的 Node.js 位于 root 私有路径：${current_node}"
    warn "systemd 服务使用 ${SERVICE_USER} 用户运行，不能依赖 root 私有 Node，将安装系统级 Node.js"
  fi

  [[ "$SKIP_DEPS" -eq 1 ]] && die "需要 Node.js >= 20.18；当前使用了 --skip-deps，无法自动安装"

  local pm
  pm="$(detect_package_manager)"
  log "准备安装 Node.js ${NODE_MAJOR}.x"

  case "$pm" in
    apt)
      curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
      apt-get install -y nodejs
      ;;
    dnf|yum)
      curl -fsSL "https://rpm.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
      "$pm" install -y nodejs
      ;;
    pacman)
      pacman -Sy --noconfirm nodejs npm
      ;;
    *)
      die "暂不支持当前包管理器；请手动安装 Node.js >= 20.18"
      ;;
  esac

  NODE_BIN="$(resolve_node_bin || true)"
  [[ -n "$NODE_BIN" ]] || die "Node.js 安装完成后仍未找到可供 systemd 使用的 Node.js >= 20.18"
  log "systemd 将使用 Node.js：$("$NODE_BIN" -v)（${NODE_BIN}）"
}

install_pnpm_with_npm() {
  log "未能使用 corepack，改用 npm 安装 pnpm@${PNPM_VERSION}"
  if ! npm install -g "pnpm@${PNPM_VERSION}"; then
    warn "npm 安装 pnpm 时遇到已有文件冲突，将使用 --force 覆盖"
    npm install -g --force "pnpm@${PNPM_VERSION}"
  fi
  add_npm_global_bin_to_path
  hash -r
}

add_npm_global_bin_to_path() {
  local npm_prefix npm_bin

  npm_prefix="$(npm prefix -g 2>/dev/null || true)"
  [[ -n "$npm_prefix" ]] || return 0

  npm_bin="${npm_prefix%/}/bin"
  [[ -d "$npm_bin" ]] || return 0

  case ":$PATH:" in
    *":${npm_bin}:"*)
      ;;
    *)
      export PATH="${npm_bin}:$PATH"
      log "已加入 npm 全局命令目录到 PATH：${npm_bin}"
      ;;
  esac
}

pnpm_available() {
  add_npm_global_bin_to_path
  command -v pnpm >/dev/null 2>&1 && pnpm --version >/dev/null 2>&1
}

setup_pnpm() {
  if pnpm_available; then
    log "检测到可用的 pnpm：$(pnpm --version)"
    return
  fi

  if command -v corepack >/dev/null 2>&1; then
    if corepack enable && corepack prepare "pnpm@${PNPM_VERSION}" --activate; then
      hash -r
    else
      warn "corepack 启用失败，将改用 npm 安装 pnpm"
      install_pnpm_with_npm
    fi
  else
    warn "当前系统没有 corepack 命令，将改用 npm 安装 pnpm"
    install_pnpm_with_npm
  fi

  pnpm_available || install_pnpm_with_npm
  pnpm_available || die "pnpm 安装失败，请手动执行：npm install -g pnpm@${PNPM_VERSION}，并把 npm 全局 bin 目录加入 PATH"
  log "已启用 pnpm：$(pnpm --version)"
}

default_api_host() {
  case "$LISTEN_HOST" in
    0.0.0.0|::)
      printf '127.0.0.1'
      ;;
    *)
      printf '%s' "$LISTEN_HOST"
      ;;
  esac
}

generate_backend_path() {
  local token

  if command -v openssl >/dev/null 2>&1; then
    token="$(openssl rand -hex 12)"
  else
    token="$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"
  fi

  [[ -n "$token" ]] || token="$(date +%s%N)"
  printf '/api-%s' "$token"
}

ensure_default_backend_path() {
  if [[ -z "$FRONTEND_BACKEND_PATH" ]]; then
    FRONTEND_BACKEND_PATH="$(generate_backend_path)"
  fi
}

normalize_backend_path() {
  local path="$1"

  [[ -n "$path" ]] || path="$(generate_backend_path)"
  [[ "$path" == /* ]] || path="/${path}"
  path="${path%/}"

  [[ -n "$path" ]] || path="/"
  [[ "$path" != "/" ]] || die "后端路径前缀不能为 /，否则前端静态页面会被后端路径吞掉；请使用 /backend 或 /你的随机路径"

  printf '%s' "$path"
}

compose_api_url() {
  local path="$1"
  printf 'http://%s:%s%s' "$(default_api_host)" "$BACKEND_PORT" "$path"
}

extract_url_path() {
  local url="$1"
  local without_scheme path

  case "$url" in
    http://*|https://*)
      without_scheme="${url#*://}"
      [[ "$without_scheme" == */* ]] || return 0
      path="/${without_scheme#*/}"
      path="${path%%\?*}"
      path="${path%%#*}"
      [[ "$path" != "/" ]] || return 0
      printf '%s' "$path"
      ;;
  esac
}

apply_api_url_input() {
  local input="$1"
  local url_path

  if [[ "$input" == /* ]]; then
    FRONTEND_BACKEND_PATH="$(normalize_backend_path "$input")"
    FRONTEND_BACKEND_PATH_EXPLICIT=1
    API_URL="$FRONTEND_BACKEND_PATH"
    return
  fi

  API_URL="$input"

  if [[ "$FRONTEND_BACKEND_PATH_EXPLICIT" -eq 0 ]]; then
    url_path="$(extract_url_path "$API_URL" || true)"
    if [[ -n "$url_path" ]]; then
      FRONTEND_BACKEND_PATH="$(normalize_backend_path "$url_path")"
    fi
  fi
}

collect_interactive_config() {
  [[ "$INTERACTIVE" -eq 1 ]] || return 0

  section "第 1 步：基础访问配置"
  LISTEN_HOST="$(prompt_default "后端监听地址 SUB_STORE_BACKEND_API_HOST" "$LISTEN_HOST")"
  BACKEND_PORT="$(prompt_default "后端监听端口 SUB_STORE_BACKEND_API_PORT" "$BACKEND_PORT")"
  ensure_default_backend_path
  FRONTEND_BACKEND_PATH="$(normalize_backend_path "$(prompt_default "后端访问路径前缀 SUB_STORE_FRONTEND_BACKEND_PATH" "$FRONTEND_BACKEND_PATH")")"
  FRONTEND_BACKEND_PATH_EXPLICIT=1

  if [[ -z "$API_URL" ]]; then
    API_URL="$FRONTEND_BACKEND_PATH"
  fi
  apply_api_url_input "$(prompt_default "前端写入的后端访问地址 VITE_API_URL（可直接输入 /自定义路径；同源部署推荐相对路径）" "$API_URL")"

  CORS_ALLOWED_ORIGINS="$(prompt_default "CORS 允许来源 SUB_STORE_CORS_ALLOWED_ORIGINS" "$CORS_ALLOWED_ORIGINS")"
  INSTALL_DIR="$(prompt_default "安装目录" "$INSTALL_DIR")"
  DATA_DIR="$(prompt_default "数据目录 SUB_STORE_DATA_BASE_PATH" "$DATA_DIR")"

  collect_interactive_backup_config \
    "第 2 步：脚本本地备份配置" \
    "第 3 步：WebDAV 远程备份配置" \
    "第 4 步：官方备份配置"

  section "第 5 步：高级官方配置"
  if confirm "进入其他官方高级配置？" "n"; then
    BACKEND_SYNC_CRON="$(prompt_default "订阅同步 cron SUB_STORE_BACKEND_SYNC_CRON（空为关闭）" "$BACKEND_SYNC_CRON")"
    PRODUCE_CRON="$(prompt_default "产物生成 cron SUB_STORE_PRODUCE_CRON（空为关闭）" "$PRODUCE_CRON")"
    DATA_URL="$(prompt_default "启动时恢复数据 URL SUB_STORE_DATA_URL（空为关闭）" "$DATA_URL")"
    DATA_URL_POST="$(prompt_default "恢复后处理脚本 SUB_STORE_DATA_URL_POST（空为关闭）" "$DATA_URL_POST")"
    BACKEND_DEFAULT_PROXY="$(prompt_default "默认代理 SUB_STORE_BACKEND_DEFAULT_PROXY（空为关闭）" "$BACKEND_DEFAULT_PROXY")"
    PUSH_SERVICE="$(prompt_default "推送服务 SUB_STORE_PUSH_SERVICE（空为关闭）" "$PUSH_SERVICE")"
  fi
}

collect_interactive_backup_config() {
  local webdav_default
  local local_title="${1:-备份配置：脚本本地备份}"
  local webdav_title="${2:-备份配置：WebDAV 远程备份}"
  local official_title="${3:-备份配置：官方 Gist 备份}"

  [[ "$INTERACTIVE" -eq 1 ]] || return 0

  section "$local_title"
  if confirm "启用脚本本地自动备份？会把数据和配置打包到本机" "y"; then
    LOCAL_BACKUP_DIR="$(prompt_default "本地备份目录 SUB_STORE_LOCAL_BACKUP_DIR" "$LOCAL_BACKUP_DIR")"
    LOCAL_BACKUP_KEEP="$(prompt_default "本地备份保留数量 SUB_STORE_LOCAL_BACKUP_KEEP" "$LOCAL_BACKUP_KEEP")"
    LOCAL_BACKUP_CRON="$(prompt_default "本地自动备份时间 SUB_STORE_LOCAL_BACKUP_CRON（daily/hourly/off 或 systemd OnCalendar）" "$LOCAL_BACKUP_CRON")"
  else
    LOCAL_BACKUP_CRON="off"
  fi

  section "$webdav_title"
  webdav_default="n"
  [[ -n "$WEBDAV_URL" ]] && webdav_default="y"
  if confirm "启用 WebDAV 远程备份？本地备份成功后自动上传 tar.gz" "$webdav_default"; then
    WEBDAV_URL="$(prompt_default "WebDAV 服务地址 SUB_STORE_WEBDAV_URL" "$WEBDAV_URL")"
    WEBDAV_USERNAME="$(prompt_default "WebDAV 用户名 SUB_STORE_WEBDAV_USERNAME（空为不使用认证）" "$WEBDAV_USERNAME")"
    WEBDAV_PASSWORD="$(prompt_secret_default "WebDAV 密码 SUB_STORE_WEBDAV_PASSWORD" "$WEBDAV_PASSWORD")"
    WEBDAV_PATH="$(prompt_default "WebDAV 远程目录 SUB_STORE_WEBDAV_PATH" "$WEBDAV_PATH")"
    WEBDAV_KEEP="$(prompt_default "WebDAV 远程保留数量 SUB_STORE_WEBDAV_KEEP" "$WEBDAV_KEEP")"
  else
    WEBDAV_URL=""
    WEBDAV_USERNAME=""
    WEBDAV_PASSWORD=""
  fi

  section "$official_title"
  if confirm "启用官方 Gist 自动上传备份 cron？需要先在前端设置 GitHub Token" "y"; then
    BACKUP_UPLOAD_CRON="$(prompt_default "上传备份 cron SUB_STORE_BACKEND_UPLOAD_CRON" "$BACKUP_UPLOAD_CRON")"
  else
    BACKUP_UPLOAD_CRON=""
  fi

  if confirm "配置官方 Gist 自动下载恢复 cron？它会用远端备份覆盖本地数据" "n"; then
    BACKUP_DOWNLOAD_CRON="$(prompt_default "下载恢复 cron SUB_STORE_BACKEND_DOWNLOAD_CRON" "0 4 * * *")"
  fi
}

normalize_webdav_path() {
  local path="$1"

  [[ -n "$path" ]] || path="/sub-store"
  [[ "$path" == /* ]] || path="/${path}"
  path="${path%/}"
  [[ -n "$path" ]] || path="/"
  printf '%s' "$path"
}

trim_value() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

normalize_local_backup_cron() {
  local value lower
  value="$(trim_value "$1")"
  lower="${value,,}"

  case "$lower" in
    ""|on|yes|y|true|1|enable|enabled|启用|开启)
      printf 'daily'
      ;;
    off|no|n|false|0|disable|disabled|禁用|关闭)
      printf 'off'
      ;;
    *)
      printf '%s' "$value"
      ;;
  esac
}

validate_local_backup_cron() {
  local result

  local_backup_enabled || return 0
  command -v systemd-analyze >/dev/null 2>&1 || return 0

  if ! result="$(systemd-analyze calendar "$LOCAL_BACKUP_CRON" 2>&1)"; then
    die "本地自动备份时间无效：${LOCAL_BACKUP_CRON}。请填写 daily、hourly、*-*-* 04:00:00 这类 systemd OnCalendar，或填写 off 关闭"
  fi
}

normalize_config() {
  [[ "$BACKEND_PORT" =~ ^[0-9]+$ ]] || die "--port 必须是数字"
  (( BACKEND_PORT >= 1 && BACKEND_PORT <= 65535 )) || die "--port 必须在 1 到 65535 之间"
  [[ "$LOCAL_BACKUP_KEEP" =~ ^[0-9]+$ ]] || die "--backup-keep 必须是数字"
  (( LOCAL_BACKUP_KEEP >= 1 )) || die "--backup-keep 必须大于等于 1"
  [[ "$WEBDAV_KEEP" =~ ^[0-9]+$ ]] || die "--webdav-keep 必须是数字"
  (( WEBDAV_KEEP >= 1 )) || die "--webdav-keep 必须大于等于 1"

  ensure_default_backend_path
  FRONTEND_BACKEND_PATH="$(normalize_backend_path "$FRONTEND_BACKEND_PATH")"

  if [[ -z "$API_URL" ]]; then
    API_URL="$FRONTEND_BACKEND_PATH"
  else
    apply_api_url_input "$API_URL"
  fi

  INSTALL_DIR="${INSTALL_DIR%/}"
  DATA_DIR="${DATA_DIR%/}"
  CONFIG_DIR="${CONFIG_DIR%/}"
  LOCAL_BACKUP_DIR="${LOCAL_BACKUP_DIR%/}"
  [[ -n "$LOCAL_BACKUP_DIR" ]] || LOCAL_BACKUP_DIR="${INSTALL_DIR}/backups"
  LOCAL_BACKUP_CRON="$(normalize_local_backup_cron "$LOCAL_BACKUP_CRON")"
  validate_local_backup_cron
  WEBDAV_URL="${WEBDAV_URL%/}"
  WEBDAV_PATH="$(normalize_webdav_path "$WEBDAV_PATH")"
}

ensure_user() {
  if id "$SERVICE_USER" >/dev/null 2>&1; then
    return
  fi

  local shell="/usr/sbin/nologin"
  [[ -x "$shell" ]] || shell="/bin/false"
  useradd --system --home-dir "$INSTALL_DIR" --shell "$shell" "$SERVICE_USER"
}

sync_repo() {
  local repo="$1"
  local branch="$2"
  local dest="$3"

  if [[ -d "$dest/.git" ]]; then
    git config --global --add safe.directory "$dest" >/dev/null 2>&1 || true
    log "更新源码目录：${dest}"
    git -C "$dest" fetch origin "$branch" --depth=1
    git -C "$dest" checkout "$branch" 2>/dev/null || git -C "$dest" checkout -B "$branch" "origin/${branch}"
    git -C "$dest" pull --ff-only origin "$branch"
  else
    [[ ! -e "$dest" ]] || die "${dest} 已存在，但不是 Git 仓库；请换安装目录或手动处理该目录"
    log "克隆源码：${repo}（分支：${branch}）"
    git clone --depth=1 --branch "$branch" "$repo" "$dest"
    git config --global --add safe.directory "$dest" >/dev/null 2>&1 || true
  fi
}

pnpm_install() {
  if [[ -f pnpm-lock.yaml ]]; then
    pnpm install --frozen-lockfile || pnpm install
  else
    pnpm install
  fi
}

write_frontend_env() {
  local frontend_dir="$1"

  cat > "${frontend_dir}/.env.production" <<EOF
ENV=production
VITE_API_URL=${API_URL}
VITE_PUBLIC_PATH=/
EOF
}

build_backend() {
  local backend_dir="${INSTALL_DIR}/Sub-Store/backend"

  log "构建 Sub-Store 后端"
  cd "$backend_dir"
  pnpm_install
  pnpm bundle:esbuild
  [[ -f "${backend_dir}/dist/sub-store.bundle.js" ]] || die "未找到后端构建产物：dist/sub-store.bundle.js"
}

build_frontend() {
  local frontend_dir="${INSTALL_DIR}/Sub-Store-Front-End"

  log "构建 Sub-Store 前端"
  write_frontend_env "$frontend_dir"
  cd "$frontend_dir"
  pnpm_install
  pnpm build
  [[ -f "${frontend_dir}/dist/index.html" ]] || die "未找到前端构建产物：dist/index.html"
}

escape_env_value() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "$value"
}

write_env_line() {
  local key="$1"
  local value="$2"
  [[ -n "$value" ]] || return 0
  printf '%s=' "$key"
  escape_env_value "$value"
  printf '\n'
}

write_env_line_always() {
  local key="$1"
  local value="$2"
  printf '%s=' "$key"
  escape_env_value "$value"
  printf '\n'
}

env_file_path() {
  printf '%s/%s.env' "$CONFIG_DIR" "$SERVICE_NAME"
}

service_file_path() {
  printf '/etc/systemd/system/%s.service' "$SERVICE_NAME"
}

backup_service_template_path() {
  printf '/etc/systemd/system/sub-store-local-backup@.service'
}

backup_timer_path() {
  printf '/etc/systemd/system/sub-store-local-backup@%s.timer' "$SERVICE_NAME"
}

backup_timer_unit_name() {
  printf 'sub-store-local-backup@%s.timer' "$SERVICE_NAME"
}

env_key_exists() {
  local key="$1"
  local file="$2"

  [[ -f "$file" ]] || return 1
  grep -Eq "^${key}=" "$file"
}

read_env_value() {
  local key="$1"
  local file="$2"
  local line value

  [[ -f "$file" ]] || return 0
  line="$(grep -E "^${key}=" "$file" | tail -n 1 || true)"
  [[ -n "$line" ]] || return 0
  value="${line#*=}"
  value="${value%\"}"
  value="${value#\"}"
  value="${value//\\\"/\"}"
  value="${value//\\\\/\\}"
  printf '%s' "$value"
}

read_frontend_api_url() {
  local file="${INSTALL_DIR}/Sub-Store-Front-End/.env.production"
  local line

  [[ -f "$file" ]] || return 0
  line="$(grep -E '^VITE_API_URL=' "$file" | tail -n 1 || true)"
  [[ -n "$line" ]] || return 0
  printf '%s' "${line#*=}"
}

redact_env_value() {
  local key="$1"
  local value="$2"

  case "$key" in
    SUB_STORE_FRONTEND_BACKEND_PATH|\
    SUB_STORE_DATA_URL|\
    SUB_STORE_DATA_URL_POST|\
    SUB_STORE_BACKEND_DEFAULT_PROXY|\
    SUB_STORE_PUSH_SERVICE|\
    *TOKEN*|*SECRET*|*PASSWORD*|*PASS*|*KEY*|*PROXY*|*URL*)
      if [[ -n "$value" ]]; then
        printf '"***已隐藏，使用 --show-secrets 可查看***"'
      else
        printf '%s' "$value"
      fi
      ;;
    *)
      printf '%s' "$value"
      ;;
  esac
}

print_env_file_redacted() {
  local file="$1"
  local line key value

  if [[ "$SHOW_SECRETS" -eq 1 ]]; then
    warn "已按 --show-secrets 显示原始环境文件，请不要把输出公开分享"
    sed -n '1,220p' "$file"
    return
  fi

  warn "以下配置默认隐藏敏感值；需要排障时可加 --show-secrets 显示原文"
  while IFS= read -r line; do
    if [[ -z "$line" || "$line" == \#* || "$line" != *=* ]]; then
      printf '%s\n' "$line"
      continue
    fi

    key="${line%%=*}"
    value="${line#*=}"
    printf '%s=%s\n' "$key" "$(redact_env_value "$key" "$value")"
  done < "$file"
}

print_systemd_unit_status() {
  local unit="$1"
  local load_state active_state sub_state unit_file_state main_pid fragment_path

  if [[ "$SHOW_SECRETS" -eq 1 ]]; then
    warn "已按 --show-secrets 显示完整 systemd 状态；最近日志可能包含后端路径前缀，请不要公开分享"
    systemctl --no-pager --full status "$unit" || true
    return
  fi

  warn "默认隐藏 systemd 最近日志，避免暴露后端路径；排障时可加 --show-secrets 查看完整状态"
  load_state="$(systemctl show "$unit" -p LoadState --value 2>/dev/null || true)"
  active_state="$(systemctl show "$unit" -p ActiveState --value 2>/dev/null || true)"
  sub_state="$(systemctl show "$unit" -p SubState --value 2>/dev/null || true)"
  unit_file_state="$(systemctl is-enabled "$unit" 2>/dev/null || true)"
  main_pid="$(systemctl show "$unit" -p MainPID --value 2>/dev/null || true)"
  fragment_path="$(systemctl show "$unit" -p FragmentPath --value 2>/dev/null || true)"

  cat <<EOF
单元名称：${unit}
加载状态：${load_state:-未知}
运行状态：${active_state:-未知}$([[ -n "$sub_state" ]] && printf ' (%s)' "$sub_state")
开机自启：${unit_file_state:-未知}
主进程 PID：${main_pid:-未知}
服务文件：${fragment_path:-未知}
EOF
}

load_existing_config() {
  local env_file
  env_file="$(env_file_path)"

  [[ -f "$env_file" ]] || return 0

  LISTEN_HOST="$(read_env_value "SUB_STORE_BACKEND_API_HOST" "$env_file" || true)"
  BACKEND_PORT="$(read_env_value "SUB_STORE_BACKEND_API_PORT" "$env_file" || true)"
  CORS_ALLOWED_ORIGINS="$(read_env_value "SUB_STORE_CORS_ALLOWED_ORIGINS" "$env_file" || true)"
  DATA_DIR="$(read_env_value "SUB_STORE_DATA_BASE_PATH" "$env_file" || true)"
  FRONTEND_BACKEND_PATH="$(read_env_value "SUB_STORE_FRONTEND_BACKEND_PATH" "$env_file" || true)"
  BACKUP_UPLOAD_CRON="$(read_env_value "SUB_STORE_BACKEND_UPLOAD_CRON" "$env_file" || true)"
  BACKUP_DOWNLOAD_CRON="$(read_env_value "SUB_STORE_BACKEND_DOWNLOAD_CRON" "$env_file" || true)"
  LOCAL_BACKUP_DIR="$(read_env_value "SUB_STORE_LOCAL_BACKUP_DIR" "$env_file" || true)"
  LOCAL_BACKUP_KEEP="$(read_env_value "SUB_STORE_LOCAL_BACKUP_KEEP" "$env_file" || true)"
  if env_key_exists "SUB_STORE_LOCAL_BACKUP_CRON" "$env_file"; then
    LOCAL_BACKUP_CRON="$(read_env_value "SUB_STORE_LOCAL_BACKUP_CRON" "$env_file" || true)"
  fi
  WEBDAV_URL="$(read_env_value "SUB_STORE_WEBDAV_URL" "$env_file" || true)"
  WEBDAV_USERNAME="$(read_env_value "SUB_STORE_WEBDAV_USERNAME" "$env_file" || true)"
  WEBDAV_PASSWORD="$(read_env_value "SUB_STORE_WEBDAV_PASSWORD" "$env_file" || true)"
  WEBDAV_PATH="$(read_env_value "SUB_STORE_WEBDAV_PATH" "$env_file" || true)"
  WEBDAV_KEEP="$(read_env_value "SUB_STORE_WEBDAV_KEEP" "$env_file" || true)"
  BACKEND_SYNC_CRON="$(read_env_value "SUB_STORE_BACKEND_SYNC_CRON" "$env_file" || true)"
  PRODUCE_CRON="$(read_env_value "SUB_STORE_PRODUCE_CRON" "$env_file" || true)"
  DATA_URL="$(read_env_value "SUB_STORE_DATA_URL" "$env_file" || true)"
  DATA_URL_POST="$(read_env_value "SUB_STORE_DATA_URL_POST" "$env_file" || true)"
  BACKEND_DEFAULT_PROXY="$(read_env_value "SUB_STORE_BACKEND_DEFAULT_PROXY" "$env_file" || true)"
  PUSH_SERVICE="$(read_env_value "SUB_STORE_PUSH_SERVICE" "$env_file" || true)"

  LISTEN_HOST="${LISTEN_HOST:-0.0.0.0}"
  BACKEND_PORT="${BACKEND_PORT:-3000}"
  CORS_ALLOWED_ORIGINS="${CORS_ALLOWED_ORIGINS:-*}"
  DATA_DIR="${DATA_DIR:-/opt/sub-store/data}"
  FRONTEND_BACKEND_PATH="${FRONTEND_BACKEND_PATH:-/backend}"
  LOCAL_BACKUP_DIR="${LOCAL_BACKUP_DIR:-/opt/sub-store/backups}"
  LOCAL_BACKUP_KEEP="${LOCAL_BACKUP_KEEP:-7}"
  WEBDAV_PATH="${WEBDAV_PATH:-/sub-store}"
  WEBDAV_KEEP="${WEBDAV_KEEP:-7}"
  if ! env_key_exists "SUB_STORE_LOCAL_BACKUP_CRON" "$env_file"; then
    LOCAL_BACKUP_CRON="${LOCAL_BACKUP_CRON:-daily}"
  fi
  if [[ -z "$API_URL" ]]; then
    API_URL="$(read_frontend_api_url || true)"
  fi
}

validate_extra_env_pair() {
  local pair="$1"
  local key="${pair%%=*}"

  [[ "$pair" == *=* ]] || die "--env 参数格式必须是 KEY=VALUE"
  [[ "$key" == SUB_STORE_* ]] || die "--env 只接受 SUB_STORE_* 形式的官方环境变量，当前是：${key}"
}

write_environment_file() {
  local env_file
  local frontend_dist="${INSTALL_DIR}/Sub-Store-Front-End/dist"
  env_file="$(env_file_path)"

  mkdir -p "$CONFIG_DIR"

  {
    printf '# 由 install_sub_store.sh 自动生成\n'
    write_env_line "SUB_STORE_BACKEND_API_HOST" "$LISTEN_HOST"
    write_env_line "SUB_STORE_BACKEND_API_PORT" "$BACKEND_PORT"
    write_env_line "SUB_STORE_CORS_ALLOWED_ORIGINS" "$CORS_ALLOWED_ORIGINS"
    write_env_line "SUB_STORE_DATA_BASE_PATH" "$DATA_DIR"
    write_env_line "SUB_STORE_BACKEND_MERGE" "1"
    write_env_line "SUB_STORE_FRONTEND_PATH" "$frontend_dist"
    write_env_line "SUB_STORE_FRONTEND_BACKEND_PATH" "$FRONTEND_BACKEND_PATH"
    write_env_line "SUB_STORE_BACKEND_UPLOAD_CRON" "$BACKUP_UPLOAD_CRON"
    write_env_line "SUB_STORE_BACKEND_DOWNLOAD_CRON" "$BACKUP_DOWNLOAD_CRON"
    write_env_line "SUB_STORE_LOCAL_BACKUP_DIR" "$LOCAL_BACKUP_DIR"
    write_env_line "SUB_STORE_LOCAL_BACKUP_KEEP" "$LOCAL_BACKUP_KEEP"
    write_env_line_always "SUB_STORE_LOCAL_BACKUP_CRON" "$LOCAL_BACKUP_CRON"
    write_env_line "SUB_STORE_WEBDAV_URL" "$WEBDAV_URL"
    if [[ -n "$WEBDAV_URL" ]]; then
      write_env_line "SUB_STORE_WEBDAV_USERNAME" "$WEBDAV_USERNAME"
      write_env_line "SUB_STORE_WEBDAV_PASSWORD" "$WEBDAV_PASSWORD"
      write_env_line "SUB_STORE_WEBDAV_PATH" "$WEBDAV_PATH"
      write_env_line "SUB_STORE_WEBDAV_KEEP" "$WEBDAV_KEEP"
    fi
    write_env_line "SUB_STORE_BACKEND_SYNC_CRON" "$BACKEND_SYNC_CRON"
    write_env_line "SUB_STORE_PRODUCE_CRON" "$PRODUCE_CRON"
    write_env_line "SUB_STORE_DATA_URL" "$DATA_URL"
    write_env_line "SUB_STORE_DATA_URL_POST" "$DATA_URL_POST"
    write_env_line "SUB_STORE_BACKEND_DEFAULT_PROXY" "$BACKEND_DEFAULT_PROXY"
    write_env_line "SUB_STORE_PUSH_SERVICE" "$PUSH_SERVICE"

    local pair key value
    for pair in "${EXTRA_ENV_PAIRS[@]}"; do
      validate_extra_env_pair "$pair"
      key="${pair%%=*}"
      value="${pair#*=}"
      write_env_line "$key" "$value"
    done
  } > "$env_file"

  chmod 0640 "$env_file"
  chown root:"$SERVICE_USER" "$env_file"
  log "已写入环境配置：${env_file}"
}

write_systemd_service() {
  local service_file env_file private_tmp_line
  local backend_dir="${INSTALL_DIR}/Sub-Store/backend"
  local bundle="${backend_dir}/dist/sub-store.bundle.js"
  service_file="$(service_file_path)"
  env_file="$(env_file_path)"
  NODE_BIN="${NODE_BIN:-$(resolve_node_bin || true)}"
  [[ -n "$NODE_BIN" ]] || die "写入 systemd 服务前未找到可用 Node.js"
  private_tmp_line="PrivateTmp=true"
  case "$backend_dir" in
    /tmp/*|/var/tmp/*)
      private_tmp_line=""
      ;;
  esac
  case "$DATA_DIR" in
    /tmp/*|/var/tmp/*)
      private_tmp_line=""
      ;;
  esac

  cat > "$service_file" <<EOF
[Unit]
Description=Sub-Store 前后端服务
Documentation=https://github.com/sub-store-org/Sub-Store
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_USER}
WorkingDirectory=${backend_dir}
EnvironmentFile=${env_file}
ExecStart=${NODE_BIN} ${bundle}
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
${private_tmp_line}

[Install]
WantedBy=multi-user.target
EOF

  chmod 0644 "$service_file"
  log "已写入 systemd 服务：${service_file}"
}

local_backup_enabled() {
  [[ -n "$LOCAL_BACKUP_CRON" && "$LOCAL_BACKUP_CRON" != "off" ]]
}

write_installer_copy() {
  local source="$ORIGINAL_SCRIPT_PATH"

  [[ -r "$source" ]] || source="${BASH_SOURCE[0]}"
  [[ -r "$source" ]] || source="$0"
  [[ -r "$source" ]] || {
    warn "无法复制当前安装脚本到 ${INSTALLER_BIN}，本地自动备份 timer 将不会启用"
    return 1
  }

  install -m 0755 "$source" "$INSTALLER_BIN"
  log "已写入脚本命令：${INSTALLER_BIN}"
}

remove_backup_timer() {
  local timer_file timer_unit
  timer_file="$(backup_timer_path)"
  timer_unit="$(backup_timer_unit_name)"

  systemctl disable --now "$timer_unit" >/dev/null 2>&1 || true
  rm -f "$timer_file"
}

write_backup_timer() {
  local service_file timer_file timer_unit
  service_file="$(backup_service_template_path)"
  timer_file="$(backup_timer_path)"
  timer_unit="$(backup_timer_unit_name)"

  if ! local_backup_enabled; then
    remove_backup_timer
    systemctl daemon-reload
    warn "脚本本地自动备份 timer 已关闭"
    return
  fi

  write_installer_copy || return 0

  cat > "$service_file" <<EOF
[Unit]
Description=Sub-Store 本地备份任务（%i）
Documentation=https://github.com/qimaoww/sub-store-installer

[Service]
Type=oneshot
ExecStart=${INSTALLER_BIN} backup --non-interactive --yes --service-name %i --install-dir "${INSTALL_DIR}" --data-dir "${DATA_DIR}" --backup-dir "${LOCAL_BACKUP_DIR}" --backup-keep "${LOCAL_BACKUP_KEEP}" --backup-reason auto
EOF

  cat > "$timer_file" <<EOF
[Unit]
Description=Sub-Store 本地自动备份定时器（${SERVICE_NAME}）

[Timer]
OnCalendar=${LOCAL_BACKUP_CRON}
Persistent=true
Unit=sub-store-local-backup@${SERVICE_NAME}.service

[Install]
WantedBy=timers.target
EOF

  chmod 0644 "$service_file" "$timer_file"
  enable_backup_timer "$timer_unit"
}

enable_backup_timer() {
  local timer_unit="$1"

  systemctl daemon-reload

  if [[ "$START_SERVICE" -eq 1 ]]; then
    systemctl enable --now "$timer_unit"
    log "已启用本地自动备份 timer：${timer_unit}（${LOCAL_BACKUP_CRON}）"
  else
    warn "已使用 --no-start，因此只写入本地自动备份 timer 文件，不启用也不启动"
  fi
}

webdav_enabled() {
  [[ -n "$WEBDAV_URL" ]]
}

webdav_curl() {
  local method="$1"
  shift
  local -a args

  args=(-fsS)
  [[ -n "$method" ]] && args+=(-X "$method")
  if [[ -n "$WEBDAV_USERNAME" || -n "$WEBDAV_PASSWORD" ]]; then
    args+=(-u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}")
  fi

  curl "${args[@]}" "$@"
}

build_webdav_collection_url() {
  local path="${WEBDAV_PATH#/}"

  if [[ -z "$path" ]]; then
    printf '%s/' "${WEBDAV_URL%/}"
  else
    printf '%s/%s/' "${WEBDAV_URL%/}" "$path"
  fi
}

build_webdav_backup_url() {
  local filename="$1"
  printf '%s%s' "$(build_webdav_collection_url)" "$filename"
}

ensure_webdav_collection() {
  local path="${WEBDAV_PATH#/}"
  local current="${WEBDAV_URL%/}"
  local segment
  local old_ifs="$IFS"

  webdav_enabled || return 0
  [[ -n "$path" ]] || return 0

  IFS='/'
  for segment in $path; do
    [[ -n "$segment" ]] || continue
    current="${current}/${segment}"
    webdav_curl "MKCOL" "${current}/" >/dev/null 2>&1 || true
  done
  IFS="$old_ifs"
}

list_webdav_backup_names() {
  local collection href name
  local response

  webdav_enabled || return 0
  collection="$(build_webdav_collection_url)"
  response="$(webdav_curl "PROPFIND" -H "Depth: 1" "$collection" 2>/dev/null || true)"
  [[ -n "$response" ]] || return 0

  printf '%s\n' "$response" \
    | sed -nE 's/.*<[^>]*href[^>]*>([^<]+)<\/[^>]*href>.*/\1/p' \
    | while IFS= read -r href; do
        name="${href##*/}"
        name="${name//%20/ }"
        [[ "$name" == "${SERVICE_NAME}-"*.tar.gz ]] || continue
        printf '%s\n' "$name"
      done
}

delete_webdav_backup() {
  local filename="$1"
  local target

  target="$(build_webdav_backup_url "$filename")"
  if webdav_curl "DELETE" "$target" >/dev/null 2>&1; then
    log "已清理 WebDAV 旧备份：${filename}"
  else
    warn "WebDAV 旧备份清理失败：${filename}"
  fi
}

cleanup_webdav_backups() {
  local keep="${WEBDAV_KEEP:-$LOCAL_BACKUP_KEEP}"
  local name timestamp

  webdav_enabled || return 0
  [[ "$keep" =~ ^[0-9]+$ ]] || return 0

  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    delete_webdav_backup "$name"
  done < <(
    while IFS= read -r name; do
      timestamp="$(printf '%s\n' "$name" | sed -nE "s/^${SERVICE_NAME}-.*-([0-9]{8}-[0-9]{6})\\.tar\\.gz$/\\1/p")"
      [[ -n "$timestamp" ]] || continue
      printf '%s %s\n' "$timestamp" "$name"
    done < <(list_webdav_backup_names) | sort -r | tail -n +"$((keep + 1))" | cut -d' ' -f2-
  )
}

upload_webdav_backup() {
  local file="$1"
  local target

  webdav_enabled || return 0
  [[ -f "$file" ]] || {
    warn "WebDAV 上传失败：本地备份文件不存在：${file}"
    return 1
  }

  ensure_webdav_collection
  target="$(build_webdav_backup_url "$(basename "$file")")"

  if webdav_curl "" -T "$file" "$target" >/dev/null; then
    log "已上传 WebDAV 远程备份：$(basename "$file")"
    cleanup_webdav_backups
  else
    warn "WebDAV 上传失败，本地备份仍已保留：${file}"
    return 1
  fi
}

list_local_backups() {
  if [[ ! -d "$LOCAL_BACKUP_DIR" ]]; then
    warn "备份目录不存在：${LOCAL_BACKUP_DIR}"
    return 0
  fi

  mapfile -t BACKUP_LIST < <(find "$LOCAL_BACKUP_DIR" -maxdepth 1 -type f -name "${SERVICE_NAME}-*.tar.gz" -printf '%T@ %p\n' | sort -rn | cut -d' ' -f2-)

  if [[ "${#BACKUP_LIST[@]}" -eq 0 ]]; then
    warn "当前没有本地备份：${LOCAL_BACKUP_DIR}"
    return 0
  fi

  local index file size
  section "本地备份列表"
  index=1
  for file in "${BACKUP_LIST[@]}"; do
    size="$(du -h "$file" | awk '{print $1}')"
    printf '  %s) %s  %s\n' "$index" "$size" "$file"
    index=$((index + 1))
  done
}

cleanup_local_backups() {
  local keep="${1:-$LOCAL_BACKUP_KEEP}"
  local deleted=0

  [[ "$keep" =~ ^[0-9]+$ ]] || die "备份保留数量必须是数字"
  [[ -d "$LOCAL_BACKUP_DIR" ]] || return 0

  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    rm -f "$file"
    deleted=$((deleted + 1))
    log "已清理旧备份：${file}"
  done < <(find "$LOCAL_BACKUP_DIR" -maxdepth 1 -type f -name "${SERVICE_NAME}-*.tar.gz" -printf '%T@ %p\n' | sort -rn | tail -n +"$((keep + 1))" | cut -d' ' -f2-)

  [[ "$deleted" -gt 0 ]] || log "没有需要清理的旧备份"
}

create_local_backup() {
  local reason="${1:-$BACKUP_REASON}"
  local timestamp filename target tmp_dir payload env_file service_file

  reason="${reason//[^A-Za-z0-9_-]/-}"
  timestamp="$(date +%Y%m%d-%H%M%S)"
  filename="${SERVICE_NAME}-${reason}-${timestamp}.tar.gz"
  target="${LOCAL_BACKUP_DIR}/${filename}"
  tmp_dir="$(mktemp -d)"
  payload="${tmp_dir}/sub-store-backup"
  env_file="$(env_file_path)"
  service_file="$(service_file_path)"

  mkdir -p "$LOCAL_BACKUP_DIR" "$payload/config"
  chmod 0700 "$LOCAL_BACKUP_DIR"

  if [[ -d "$DATA_DIR" ]]; then
    cp -a "$DATA_DIR" "$payload/data"
  else
    mkdir -p "$payload/data"
    warn "数据目录不存在，将创建空数据备份：${DATA_DIR}"
  fi

  [[ -f "$env_file" ]] && cp -a "$env_file" "$payload/config/${SERVICE_NAME}.env"
  [[ -f "$service_file" ]] && cp -a "$service_file" "$payload/config/${SERVICE_NAME}.service"

  {
    printf 'service_name=%s\n' "$SERVICE_NAME"
    printf 'install_dir=%s\n' "$INSTALL_DIR"
    printf 'data_dir=%s\n' "$DATA_DIR"
    printf 'created_at=%s\n' "$(date -Iseconds)"
    printf 'reason=%s\n' "$reason"
  } > "$payload/metadata"

  tar -C "$tmp_dir" -czf "$target" sub-store-backup
  chmod 0600 "$target"
  rm -rf "$tmp_dir"

  log "已创建本地备份：${target}"
  warn "备份包包含环境文件，可能包含后端路径、Token 或代理信息，请不要公开分享"
  if webdav_enabled; then
    upload_webdav_backup "$target" || true
  fi
  cleanup_local_backups "$LOCAL_BACKUP_KEEP"
  printf '%s\n' "$target"
}

select_backup_file() {
  local choice

  if [[ -n "$BACKUP_FILE" ]]; then
    [[ -f "$BACKUP_FILE" ]] || die "指定的备份文件不存在：${BACKUP_FILE}"
    printf '%s' "$BACKUP_FILE"
    return
  fi

  [[ -d "$LOCAL_BACKUP_DIR" ]] || die "备份目录不存在：${LOCAL_BACKUP_DIR}"
  mapfile -t BACKUP_LIST < <(find "$LOCAL_BACKUP_DIR" -maxdepth 1 -type f -name "${SERVICE_NAME}-*.tar.gz" -printf '%T@ %p\n' | sort -rn | cut -d' ' -f2-)
  [[ "${#BACKUP_LIST[@]}" -gt 0 ]] || die "没有可恢复的本地备份"

  if [[ "$INTERACTIVE" -eq 0 ]]; then
    printf '%s' "${BACKUP_LIST[0]}"
    return
  fi

  list_local_backups
  read_interactive "请输入要恢复的备份序号 [1]: " choice
  choice="${choice:-1}"
  [[ "$choice" =~ ^[0-9]+$ ]] || die "备份序号必须是数字"
  (( choice >= 1 && choice <= ${#BACKUP_LIST[@]} )) || die "备份序号超出范围"
  printf '%s' "${BACKUP_LIST[$((choice - 1))]}"
}

restore_local_backup() {
  local backup_file="$1"
  local tmp_dir payload env_file service_file

  [[ -f "$backup_file" ]] || die "备份文件不存在：${backup_file}"
  [[ -n "$DATA_DIR" && "$DATA_DIR" != "/" ]] || die "数据目录不安全，拒绝恢复：${DATA_DIR}"

  tmp_dir="$(mktemp -d)"
  tar -C "$tmp_dir" -xzf "$backup_file"
  payload="${tmp_dir}/sub-store-backup"
  [[ -d "$payload/data" ]] || die "备份文件格式不正确：缺少数据目录"

  env_file="$(env_file_path)"
  service_file="$(service_file_path)"

  create_local_backup "pre-restore" >/dev/null
  systemctl stop "${SERVICE_NAME}.service" >/dev/null 2>&1 || true

  mkdir -p "$(dirname "$DATA_DIR")" "$CONFIG_DIR"
  rm -rf "$DATA_DIR"
  cp -a "$payload/data" "$DATA_DIR"

  if [[ -f "$payload/config/${SERVICE_NAME}.env" ]]; then
    cp -a "$payload/config/${SERVICE_NAME}.env" "$env_file"
    chmod 0640 "$env_file"
    chown root:"$SERVICE_USER" "$env_file" || true
  fi

  if [[ -f "$payload/config/${SERVICE_NAME}.service" ]]; then
    cp -a "$payload/config/${SERVICE_NAME}.service" "$service_file"
    chmod 0644 "$service_file"
  fi

  chown -R "$SERVICE_USER:$SERVICE_USER" "$DATA_DIR" || true
  rm -rf "$tmp_dir"

  systemctl daemon-reload
  systemctl restart "${SERVICE_NAME}.service" || warn "服务重启失败，请运行 status 查看原因"
  log "已从备份恢复：${backup_file}"
}

prepare_directories() {
  mkdir -p "$INSTALL_DIR" "$DATA_DIR" "$CONFIG_DIR" "$LOCAL_BACKUP_DIR"
  chmod 0700 "$LOCAL_BACKUP_DIR"
}

fix_permissions() {
  chmod 0755 "$INSTALL_DIR"
  chown -R "$SERVICE_USER:$SERVICE_USER" "$DATA_DIR"
  chown -R "$SERVICE_USER:$SERVICE_USER" "${INSTALL_DIR}/Sub-Store" "${INSTALL_DIR}/Sub-Store-Front-End"
}

start_or_reload_service() {
  systemctl daemon-reload

  if [[ "$START_SERVICE" -eq 1 ]]; then
    systemctl enable --now "${SERVICE_NAME}.service"
    systemctl restart "${SERVICE_NAME}.service"
    section "Sub-Store 服务状态"
    print_systemd_unit_status "${SERVICE_NAME}.service"
  else
    warn "已使用 --no-start，因此没有启用或启动 systemd 服务"
  fi
}

print_summary() {
  cat <<EOF

Sub-Store 安装摘要
------------------
服务名称：      ${SERVICE_NAME}.service
监听地址：      ${LISTEN_HOST}:${BACKEND_PORT}
后端地址：      ${API_URL}
安装目录：      ${INSTALL_DIR}
数据目录：      ${DATA_DIR}
环境文件：      ${CONFIG_DIR}/${SERVICE_NAME}.env

常用命令：
  systemctl status ${SERVICE_NAME}
  journalctl -u ${SERVICE_NAME} -f
  systemctl restart ${SERVICE_NAME}

备份提示：
  SUB_STORE_BACKEND_UPLOAD_CRON=${BACKUP_UPLOAD_CRON:-已关闭}
  SUB_STORE_LOCAL_BACKUP_DIR=${LOCAL_BACKUP_DIR}
  SUB_STORE_LOCAL_BACKUP_KEEP=${LOCAL_BACKUP_KEEP}
  SUB_STORE_LOCAL_BACKUP_CRON=${LOCAL_BACKUP_CRON:-已关闭}
  SUB_STORE_WEBDAV_URL=$([[ -n "$WEBDAV_URL" ]] && printf '已配置' || printf '已关闭')
  官方 Gist 备份需要先在 Sub-Store 前端设置里配置 GitHub Token。
EOF
}

print_install_plan() {
  local start_action
  if [[ "$START_SERVICE" -eq 1 ]]; then
    start_action="启用并启动服务"
  else
    start_action="只写入服务文件，不启动服务"
  fi

  section "安装计划确认"
  cat <<EOF
脚本将按下面顺序执行：
  1. 检查 root 权限和 systemd
  2. 安装 curl、git、编译工具、Node.js 和 pnpm
  3. 克隆或更新 Sub-Store 后端源码：${BACKEND_BRANCH}
  4. 克隆或更新 Sub-Store 前端源码：${FRONTEND_BRANCH}
  5. 写入前端 VITE_API_URL：${API_URL}
  6. 构建后端和前端
  7. 写入环境文件：${CONFIG_DIR}/${SERVICE_NAME}.env
  8. 写入 systemd 服务：/etc/systemd/system/${SERVICE_NAME}.service
  9. ${start_action}

关键配置：
  监听地址：${LISTEN_HOST}:${BACKEND_PORT}
  后端访问地址：${API_URL}
  安装目录：${INSTALL_DIR}
  数据目录：${DATA_DIR}
  本地备份目录：${LOCAL_BACKUP_DIR}
  本地备份保留：${LOCAL_BACKUP_KEEP}
  本地自动备份：${LOCAL_BACKUP_CRON:-已关闭}
  WebDAV 远程备份：$([[ -n "$WEBDAV_URL" ]] && printf '已配置' || printf '已关闭')
  CORS 来源：${CORS_ALLOWED_ORIGINS}
  自动上传备份：${BACKUP_UPLOAD_CRON:-已关闭}
EOF
}

build_and_write_runtime() {
  install_base_dependencies
  install_node_if_needed
  setup_pnpm
  ensure_user
  prepare_directories
  sync_repo "$BACKEND_REPO" "$BACKEND_BRANCH" "${INSTALL_DIR}/Sub-Store"
  sync_repo "$FRONTEND_REPO" "$FRONTEND_BRANCH" "${INSTALL_DIR}/Sub-Store-Front-End"
  build_backend
  build_frontend
  write_environment_file
  write_systemd_service
  write_backup_timer
  fix_permissions
  start_or_reload_service
}

install_action() {
  collect_interactive_config
  normalize_config

  print_install_plan

  if [[ "$BACKUP_UPLOAD_CRON" == "" ]]; then
    warn "官方自动上传备份 cron 已关闭"
  else
    warn "官方自动上传备份已计划执行，但需要先在前端设置 GitHub Token"
  fi

  if [[ "$ASSUME_YES" -eq 0 && "$INTERACTIVE" -eq 1 ]]; then
    confirm "确认开始安装？" "y" || die "已取消安装"
  fi

  build_and_write_runtime
  print_summary
}

update_action() {
  local env_file
  env_file="$(env_file_path)"

  [[ -f "$env_file" ]] || die "未找到已安装配置：${env_file}；请先执行 install"

  load_existing_config
  apply_cli_overrides
  normalize_config

  section "更新已安装 Sub-Store"
  cat <<EOF
脚本将执行：
  1. 读取现有配置：${env_file}
  2. 更新后端源码分支：${BACKEND_BRANCH}
  3. 更新前端源码分支：${FRONTEND_BRANCH}
  4. 重新构建前后端
  5. 保留数据目录并重启服务

关键配置：
  安装目录：${INSTALL_DIR}
  数据目录：${DATA_DIR}
  本地备份目录：${LOCAL_BACKUP_DIR}
  更新前自动备份：$([[ "$UPDATE_BACKUP" -eq 1 ]] && printf '开启' || printf '关闭')
EOF

  confirm "确认开始更新？" "y" || die "已取消更新"

  if [[ "$UPDATE_BACKUP" -eq 1 ]]; then
    create_local_backup "pre-update" >/dev/null
  fi

  build_and_write_runtime
  print_summary
}

uninstall_action() {
  local service_file env_file
  service_file="$(service_file_path)"
  env_file="$(env_file_path)"

  load_existing_config
  apply_cli_overrides

  section "卸载计划确认"
  cat <<EOF
脚本将执行：
  1. 停止并禁用服务：${SERVICE_NAME}.service
  2. 删除服务文件：${service_file}
  3. 删除本地自动备份 timer
  4. 可选删除程序源码目录：
     - ${INSTALL_DIR}/Sub-Store
     - ${INSTALL_DIR}/Sub-Store-Front-End
  5. 可选删除环境文件：${env_file}
  6. 可选删除数据目录：${DATA_DIR}
  7. 可选删除本地备份目录：${LOCAL_BACKUP_DIR}
EOF

  confirm "确认开始卸载？" "n" || die "已取消卸载"

  systemctl disable --now "${SERVICE_NAME}.service" >/dev/null 2>&1 || true
  remove_backup_timer
  rm -f "$service_file"
  systemctl daemon-reload
  log "已停止服务并删除 systemd 服务文件"

  if confirm "删除程序源码目录？" "y"; then
    rm -rf "${INSTALL_DIR}/Sub-Store" "${INSTALL_DIR}/Sub-Store-Front-End"
    rmdir "$INSTALL_DIR" >/dev/null 2>&1 || true
    log "已删除程序源码目录"
  fi

  if confirm "删除环境文件？" "n"; then
    rm -f "$env_file"
    rmdir "$CONFIG_DIR" >/dev/null 2>&1 || true
    log "已删除环境文件"
  fi

  if confirm "删除数据目录？这会删除 Sub-Store 本地数据" "n"; then
    rm -rf "$DATA_DIR"
    log "已删除数据目录"
  else
    log "已保留数据目录：${DATA_DIR}"
  fi

  if confirm "删除本地备份目录？这会删除脚本创建的 tar.gz 备份" "n"; then
    rm -rf "$LOCAL_BACKUP_DIR"
    log "已删除本地备份目录：${LOCAL_BACKUP_DIR}"
  else
    log "已保留本地备份目录：${LOCAL_BACKUP_DIR}"
  fi
}

modify_config_action() {
  local env_file
  env_file="$(env_file_path)"

  [[ -f "$env_file" ]] || die "未找到环境文件：${env_file}；请先执行安装"

  load_existing_config
  apply_cli_overrides
  section "修改配置"
  collect_interactive_config
  normalize_config

  section "配置修改计划"
  cat <<EOF
将写入环境文件：${env_file}
服务将重启：${SERVICE_NAME}.service
新的后端地址：${API_URL}
新的监听地址：${LISTEN_HOST}:${BACKEND_PORT}
新的路径前缀：${FRONTEND_BACKEND_PATH}
EOF

  confirm "确认写入新配置并重启服务？" "y" || die "已取消修改配置"

  ensure_user
  prepare_directories
  write_environment_file
  write_backup_timer

  if [[ -d "${INSTALL_DIR}/Sub-Store-Front-End" ]] && confirm "是否按新的 VITE_API_URL 重新构建前端？" "y"; then
    setup_pnpm
    build_frontend
    fix_permissions
  fi

  systemctl daemon-reload
  systemctl restart "${SERVICE_NAME}.service"
  log "配置已更新，服务已重启"
}

backup_config_action() {
  local env_file
  env_file="$(env_file_path)"

  [[ -f "$env_file" ]] || die "未找到环境文件：${env_file}；请先执行安装"

  load_existing_config
  apply_cli_overrides
  section "只修改备份配置"
  collect_interactive_backup_config \
    "第 1 步：脚本本地备份配置" \
    "第 2 步：WebDAV 远程备份配置" \
    "第 3 步：官方备份配置"
  normalize_config

  section "备份配置修改计划"
  cat <<EOF
将写入环境文件：${env_file}
服务名称：${SERVICE_NAME}.service
监听地址保持不变：${LISTEN_HOST}:${BACKEND_PORT}
后端路径保持不变：${FRONTEND_BACKEND_PATH}
本地备份目录：${LOCAL_BACKUP_DIR}
本地备份保留：${LOCAL_BACKUP_KEEP}
本地自动备份：${LOCAL_BACKUP_CRON:-已关闭}
WebDAV 远程备份：$([[ -n "$WEBDAV_URL" ]] && printf '已配置' || printf '已关闭')
官方上传 cron：${BACKUP_UPLOAD_CRON:-已关闭}
官方下载 cron：${BACKUP_DOWNLOAD_CRON:-已关闭}
EOF

  confirm "确认写入备份配置？" "y" || die "已取消修改备份配置"

  ensure_user
  mkdir -p "$CONFIG_DIR"
  if local_backup_enabled; then
    mkdir -p "$LOCAL_BACKUP_DIR"
    chmod 0700 "$LOCAL_BACKUP_DIR"
  fi
  write_environment_file
  write_backup_timer
  systemctl daemon-reload
  if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
    systemctl try-restart "${SERVICE_NAME}.service" || warn "服务重启失败，请运行 status 查看原因"
  else
    warn "服务当前未运行，已写入配置；下次启动时生效"
  fi
  log "备份配置已更新"
}

backup_action() {
  load_existing_config
  apply_cli_overrides
  normalize_config
  section "立即创建备份"
  create_local_backup "$BACKUP_REASON"
}

webdav_test_action() {
  local collection

  load_existing_config
  apply_cli_overrides
  normalize_config
  section "测试 WebDAV 远程备份"

  webdav_enabled || die "尚未配置 WebDAV；请先执行 config 或安装时填写 WebDAV 配置"
  ensure_webdav_collection
  collection="$(build_webdav_collection_url)"

  if webdav_curl "PROPFIND" -H "Depth: 0" "$collection" >/dev/null; then
    log "WebDAV 连接正常，远程目录可访问：${collection}"
  else
    die "WebDAV 连接失败，请检查地址、用户名、密码和远程目录"
  fi
}

restore_action() {
  local selected
  load_existing_config
  apply_cli_overrides
  normalize_config
  section "从本地备份恢复"
  selected="$(select_backup_file)"
  cat <<EOF
将从下面的备份恢复：
  ${selected}

恢复会先创建当前状态备份，然后停止服务、覆盖数据目录，并尽量恢复环境文件和服务文件。
EOF
  confirm "确认开始恢复？" "n" || die "已取消恢复"
  BACKUP_FILE="$selected"
  restore_local_backup "$selected"
}

list_backups_action() {
  load_existing_config
  apply_cli_overrides
  normalize_config
  list_local_backups
}

cleanup_backups_action() {
  load_existing_config
  apply_cli_overrides
  normalize_config
  section "清理旧备份"
  cat <<EOF
备份目录：${LOCAL_BACKUP_DIR}
保留数量：${LOCAL_BACKUP_KEEP}
EOF
  confirm "确认清理旧备份？" "y" || die "已取消清理"
  cleanup_local_backups "$LOCAL_BACKUP_KEEP"
}

show_config_action() {
  local env_file service_file
  env_file="$(env_file_path)"
  service_file="$(service_file_path)"
  load_existing_config
  apply_cli_overrides

  section "当前服务状态"
  print_systemd_unit_status "${SERVICE_NAME}.service"

  section "当前环境配置"
  if [[ -f "$env_file" ]]; then
    print_env_file_redacted "$env_file"
  else
    warn "未找到环境文件：${env_file}"
  fi

  section "常用路径"
  cat <<EOF
服务文件：${service_file}
环境文件：${env_file}
安装目录：${INSTALL_DIR}
数据目录：${DATA_DIR}
本地备份目录：${LOCAL_BACKUP_DIR}
本地备份保留：${LOCAL_BACKUP_KEEP}
本地自动备份：${LOCAL_BACKUP_CRON:-已关闭}
WebDAV 远程备份：$([[ -n "$WEBDAV_URL" ]] && printf '已配置' || printf '已关闭')
WebDAV 远程目录：${WEBDAV_PATH}
EOF

  section "本地自动备份 timer"
  print_systemd_unit_status "$(backup_timer_unit_name)"
}

status_action() {
  section "Sub-Store 服务状态"
  print_systemd_unit_status "${SERVICE_NAME}.service"
}

start_action() {
  section "启动 Sub-Store 服务"
  systemctl daemon-reload
  systemctl enable --now "${SERVICE_NAME}.service"
  status_action
}

restart_action() {
  section "重启 Sub-Store 服务"
  systemctl daemon-reload
  systemctl restart "${SERVICE_NAME}.service"
  status_action
}

stop_action() {
  section "停止 Sub-Store 服务"
  systemctl stop "${SERVICE_NAME}.service"
  status_action
}

disable_action() {
  section "关闭 Sub-Store 服务"
  systemctl disable --now "${SERVICE_NAME}.service"
  status_action
}

main() {
  parse_args "$@"
  choose_action

  if [[ "$ACTION" == "exit" ]]; then
    log "已退出"
    return 0
  fi

  require_root
  require_systemd

  case "$ACTION" in
    install)
      install_action
      ;;
    update)
      update_action
      ;;
    backup)
      backup_action
      ;;
    restore)
      restore_action
      ;;
    list-backups)
      list_backups_action
      ;;
    cleanup-backups)
      cleanup_backups_action
      ;;
    webdav-test)
      webdav_test_action
      ;;
    uninstall)
      uninstall_action
      ;;
    config)
      modify_config_action
      ;;
    backup-config)
      backup_config_action
      ;;
    show)
      show_config_action
      ;;
    status)
      status_action
      ;;
    start)
      start_action
      ;;
    restart)
      restart_action
      ;;
    stop)
      stop_action
      ;;
    disable)
      disable_action
      ;;
    *)
      die "未知操作：${ACTION}"
      ;;
  esac
}

main "$@"
