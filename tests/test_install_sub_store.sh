#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/install_sub_store.sh"
README="${ROOT_DIR}/README.md"

fail() {
  printf '失败：%s\n' "$*" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "缺少文件：$1"
}

assert_contains() {
  local needle="$1"
  grep -Fq -- "$needle" "$SCRIPT" || fail "安装脚本缺少内容：$needle"
}

assert_readme_contains() {
  local needle="$1"
  grep -Fq -- "$needle" "$README" || fail "README 缺少内容：$needle"
}

assert_file "$SCRIPT"
assert_file "$README"
bash -n "$SCRIPT"

assert_contains "SUB_STORE_BACKEND_API_HOST"
assert_contains "SUB_STORE_BACKEND_API_PORT"
assert_contains "VITE_API_URL"
assert_contains "SUB_STORE_CORS_ALLOWED_ORIGINS"
assert_contains "SUB_STORE_DATA_BASE_PATH"
assert_contains "SUB_STORE_BACKEND_MERGE"
assert_contains "SUB_STORE_FRONTEND_PATH"
assert_contains "SUB_STORE_FRONTEND_BACKEND_PATH"
assert_contains "FRONTEND_BACKEND_PATH=\"\""
assert_contains "read -e -r -p"
assert_contains "/dev/tty"
assert_contains "read_interactive"
assert_contains "generate_backend_path"
assert_contains "ensure_default_backend_path"
assert_contains "set_cli_override"
assert_contains "apply_cli_overrides"
assert_contains "normalize_backend_path"
assert_contains "ORIGINAL_SCRIPT_PATH"
assert_contains "private_tmp_line"
assert_contains 'chmod 0755 "$INSTALL_DIR"'
assert_contains "可直接输入 /自定义路径"
assert_contains 'API_URL="$FRONTEND_BACKEND_PATH"'
assert_contains "相对路径"
assert_contains "不能为 /"
assert_contains "选择要执行的操作"
assert_contains '[[ -z "$ACTION" ]] || return 0'
assert_contains "menu_option"
assert_contains "menu_note"
assert_contains "说明："
assert_contains "安装与更新"
assert_contains "配置与查看"
assert_contains "备份与恢复"
assert_contains "服务控制"
assert_contains "choose_install_menu"
assert_contains "choose_config_menu"
assert_contains "choose_backup_menu"
assert_contains "choose_service_menu"
assert_contains "install_action"
assert_contains "uninstall_action"
assert_contains "modify_config_action"
assert_contains "backup_config_action"
assert_contains "show_config_action"
assert_contains "status_action"
assert_contains "start_action"
assert_contains "restart_action"
assert_contains "stop_action"
assert_contains "disable_action"
assert_contains "update_action"
assert_contains "backup_action"
assert_contains "restore_action"
assert_contains "list_backups_action"
assert_contains "cleanup_backups_action"
assert_contains "webdav_test_action"
assert_contains "collect_interactive_backup_config"
assert_contains "normalize_local_backup_cron"
assert_contains "validate_local_backup_cron"
assert_contains "只修改备份配置"
assert_contains "backup-config"
assert_contains "备份配置已更新"
assert_contains "write_backup_timer"
assert_contains "enable_backup_timer"
assert_contains "只写入本地自动备份 timer 文件"
assert_contains "create_local_backup"
assert_contains "restore_local_backup"
assert_contains "print_env_file_redacted"
assert_contains "redact_env_value"
assert_contains "print_systemd_unit_status"
assert_contains "默认隐藏 systemd 最近日志"
assert_contains "最近日志可能包含后端路径前缀"
assert_contains "SUB_STORE_LOCAL_BACKUP_DIR"
assert_contains "SUB_STORE_LOCAL_BACKUP_KEEP"
assert_contains "SUB_STORE_LOCAL_BACKUP_CRON"
assert_contains "SUB_STORE_WEBDAV_URL"
assert_contains "SUB_STORE_WEBDAV_USERNAME"
assert_contains "SUB_STORE_WEBDAV_PASSWORD"
assert_contains "SUB_STORE_WEBDAV_PATH"
assert_contains "SUB_STORE_WEBDAV_KEEP"
assert_contains "sub-store-local-backup@"
assert_contains "--backup-dir"
assert_contains "--backup-keep"
assert_contains "--local-backup-cron"
assert_contains "--webdav-url"
assert_contains "--webdav-user"
assert_contains "--webdav-password"
assert_contains "--webdav-path"
assert_contains "--webdav-keep"
assert_contains "--no-webdav"
assert_contains "webdav-test"
assert_contains "--show-secrets"
assert_contains "webdav_enabled"
assert_contains "build_webdav_backup_url"
assert_contains "ensure_webdav_collection"
assert_contains "upload_webdav_backup"
assert_contains "install_pnpm_with_npm"
assert_contains "add_npm_global_bin_to_path"
assert_contains "npm prefix -g"
assert_contains 'npm install -g "pnpm@${PNPM_VERSION}"'
assert_contains 'npm install -g --force "pnpm@${PNPM_VERSION}"'
assert_contains "检测到可用的 pnpm"
assert_contains "resolve_node_bin"
assert_contains "NODE_BIN"
assert_contains 'ExecStart=${NODE_BIN}'
assert_contains "safe.directory"
assert_contains "SUB_STORE_BACKEND_UPLOAD_CRON"
assert_contains "SUB_STORE_BACKEND_DOWNLOAD_CRON"
assert_contains "SUB_STORE_BACKEND_SYNC_CRON"
assert_contains "SUB_STORE_PRODUCE_CRON"
assert_contains "SUB_STORE_DATA_URL"
assert_contains "--env"

assert_readme_contains "bash <(curl -fsSL https://raw.githubusercontent.com/qimaoww/sub-store-installer/main/install_sub_store.sh)"
assert_readme_contains "不会写入 README 或测试文件"
assert_readme_contains "WebDAV 远程备份"
assert_readme_contains "backup-config"
assert_readme_contains '误填 `on/yes/true` 会按 `daily` 处理'

backup_config_body="$(sed -n '/^backup_config_action()/,/^backup_action()/p' "$SCRIPT")"
[[ "$backup_config_body" != *"collect_interactive_config"* ]] || fail "backup-config 不应进入完整基础配置流程"
[[ "$backup_config_body" != *"build_frontend"* ]] || fail "backup-config 不应重建前端"

bash -c '
set -euo pipefail
source <(sed "$ d" "$1")

output="$(menu_option 1 "安装 Sub-Store"; menu_note "全新源码部署")"
[[ "$output" == *$'\''\033[1m[1] 安装 Sub-Store'\''* ]] || exit 30
[[ "$output" == *$'\''\033[2m说明：全新源码部署'\''* ]] || exit 31

ASSUME_YES=1
INTERACTIVE=0
confirm "测试确认" "n" || exit 20

ASSUME_YES=0
INTERACTIVE=0
if confirm "测试确认" "n"; then
  exit 21
fi
' bash "$SCRIPT" || fail "--yes 非交互确认逻辑验证失败"

bash -c '
set -euo pipefail
source <(sed "$ d" "$1")

FRONTEND_BACKEND_PATH=""
API_URL=""
normalize_config
[[ "$FRONTEND_BACKEND_PATH" == /api-* ]] || exit 10
[[ "$API_URL" == "$FRONTEND_BACKEND_PATH" ]] || exit 11

FRONTEND_BACKEND_PATH=""
API_URL=""
apply_api_url_input "/my-custom-path"
[[ "$FRONTEND_BACKEND_PATH" == "/my-custom-path" ]] || exit 12
[[ "$API_URL" == "/my-custom-path" ]] || exit 13
' bash "$SCRIPT" || fail "随机后端路径或自定义后端路径逻辑验证失败"

bash -c '
set -euo pipefail
source <(sed "$ d" "$1")

LOCAL_BACKUP_CRON="on"
normalize_config
[[ "$LOCAL_BACKUP_CRON" == "daily" ]] || exit 20

LOCAL_BACKUP_CRON="yes"
normalize_config
[[ "$LOCAL_BACKUP_CRON" == "daily" ]] || exit 21

LOCAL_BACKUP_CRON="off"
normalize_config
[[ "$LOCAL_BACKUP_CRON" == "off" ]] || exit 22

LOCAL_BACKUP_CRON="no"
normalize_config
[[ "$LOCAL_BACKUP_CRON" == "off" ]] || exit 23

LOCAL_BACKUP_CRON="hourly"
normalize_config
[[ "$LOCAL_BACKUP_CRON" == "hourly" ]] || exit 24
' bash "$SCRIPT" || fail "本地自动备份 OnCalendar 开关兼容逻辑验证失败"

while IFS= read -r file; do
  while IFS= read -r line; do
    if [[ "$line" =~ /[A-Za-z0-9_-]{8,}\^ ]]; then
      fail "疑似真实随机后端路径被写入仓库文件：$file"
    fi
    if [[ "$line" =~ /[A-Za-z0-9_-]{18,} ]]; then
      candidate="${BASH_REMATCH[0]#/}"
      if [[ "$candidate" =~ [A-Z] && "$candidate" =~ [0-9] ]]; then
        fail "疑似真实随机后端路径被写入仓库文件：$file"
      fi
    fi
  done < "$file"
done < <(find "$ROOT_DIR" -type f \( -name '*.sh' -o -name 'README.md' \) | sort)

printf '安装脚本静态检查通过\n'
