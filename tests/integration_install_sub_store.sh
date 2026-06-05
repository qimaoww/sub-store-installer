#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${SUB_STORE_TEST_IMAGE:-debian:bookworm-slim}"

fail() {
  printf '集成测试失败：%s\n' "$*" >&2
  exit 1
}

log() {
  printf '[集成测试] %s\n' "$*"
}

if [[ "${SUB_STORE_TEST_INSIDE:-0}" != "1" ]]; then
  command -v docker >/dev/null 2>&1 || fail "未找到 docker"
  log "使用 Docker 镜像 ${IMAGE} 运行隔离测试"
  docker run --rm \
    -e SUB_STORE_TEST_INSIDE=1 \
    -v "${ROOT_DIR}:/work:ro" \
    -w /work \
    "${IMAGE}" \
    bash tests/integration_install_sub_store.sh
  exit 0
fi

TEST_ROOT="$(mktemp -d)"
FAKE_BIN="${TEST_ROOT}/fake-bin"
TEST_LOG="${TEST_ROOT}/logs"
mkdir -p "$FAKE_BIN" "$TEST_LOG" /etc/systemd/system /usr/local/bin
export SUB_STORE_TEST_LOG="$TEST_LOG"
export PATH="${FAKE_BIN}:$PATH"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

write_fake_commands() {
  cat > "${FAKE_BIN}/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'systemctl' >> "${SUB_STORE_TEST_LOG}/systemctl.log"
printf ' %q' "$@" >> "${SUB_STORE_TEST_LOG}/systemctl.log"
printf '\n' >> "${SUB_STORE_TEST_LOG}/systemctl.log"
if [[ "$*" == *status* ]]; then
  printf 'fake systemd status: active\n'
fi
exit 0
EOF

  cat > "${FAKE_BIN}/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'git' >> "${SUB_STORE_TEST_LOG}/git.log"
printf ' %q' "$@" >> "${SUB_STORE_TEST_LOG}/git.log"
printf '\n' >> "${SUB_STORE_TEST_LOG}/git.log"

if [[ "${1:-}" == "-C" ]]; then
  exit 0
fi

case "${1:-}" in
  config)
    exit 0
    ;;
  clone)
    dest="${!#}"
    base="$(basename "$dest")"
    mkdir -p "$dest/.git"
    case "$base" in
      Sub-Store)
        mkdir -p "$dest/backend"
        printf '{"scripts":{"bundle:esbuild":"true"}}\n' > "$dest/backend/package.json"
        printf 'lockfileVersion: 9\n' > "$dest/backend/pnpm-lock.yaml"
        ;;
      Sub-Store-Front-End)
        printf '{"scripts":{"build":"true"}}\n' > "$dest/package.json"
        printf 'lockfileVersion: 9\n' > "$dest/pnpm-lock.yaml"
        ;;
    esac
    ;;
esac
exit 0
EOF

  cat > "${FAKE_BIN}/pnpm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'pnpm' >> "${SUB_STORE_TEST_LOG}/pnpm.log"
printf ' %q' "$@" >> "${SUB_STORE_TEST_LOG}/pnpm.log"
printf ' cwd=%q\n' "$PWD" >> "${SUB_STORE_TEST_LOG}/pnpm.log"

case "${1:-}" in
  --version)
    printf '11.0.9\n'
    ;;
  install)
    ;;
  bundle:esbuild)
    mkdir -p dist
    printf 'console.log("fake sub-store backend");\n' > dist/sub-store.bundle.js
    ;;
  build)
    mkdir -p dist
    printf '<!doctype html><title>fake sub-store frontend</title>\n' > dist/index.html
    ;;
esac
EOF

  cat > "${FAKE_BIN}/node" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-v" ]]; then
  printf 'v22.22.2\n'
  exit 0
fi
printf 'fake node %s\n' "$*" >> "${SUB_STORE_TEST_LOG}/node.log"
EOF

  cat > "${FAKE_BIN}/npm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "prefix" && "${2:-}" == "-g" ]]; then
  mkdir -p /tmp/sub-store-fake-npm/bin
  printf '/tmp/sub-store-fake-npm\n'
  exit 0
fi
printf 'npm' >> "${SUB_STORE_TEST_LOG}/npm.log"
printf ' %q' "$@" >> "${SUB_STORE_TEST_LOG}/npm.log"
printf '\n' >> "${SUB_STORE_TEST_LOG}/npm.log"
exit 0
EOF

  cat > "${FAKE_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
method=""
upload=""
url=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -X)
      method="$2"
      shift 2
      ;;
    -T)
      upload="$2"
      shift 2
      ;;
    -u|-H)
      shift 2
      ;;
    -*)
      shift
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done
printf 'curl method=%q upload=%q url=%q\n' "$method" "$upload" "$url" >> "${SUB_STORE_TEST_LOG}/curl.log"
if [[ "$method" == "PROPFIND" ]]; then
  cat <<'XML'
<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:">
  <d:response><d:href>/substore-it/</d:href></d:response>
  <d:response><d:href>/substore-it/sub-store-it-webdav-old-20240101-000000.tar.gz</d:href></d:response>
</d:multistatus>
XML
fi
exit 0
EOF

  cat > "${FAKE_BIN}/id" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "substore" ]]; then
  exit 0
fi
/usr/bin/id "$@"
EOF

  cat > "${FAKE_BIN}/useradd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'useradd' >> "${SUB_STORE_TEST_LOG}/useradd.log"
printf ' %q' "$@" >> "${SUB_STORE_TEST_LOG}/useradd.log"
printf '\n' >> "${SUB_STORE_TEST_LOG}/useradd.log"
EOF

  cat > "${FAKE_BIN}/chown" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'chown' >> "${SUB_STORE_TEST_LOG}/chown.log"
printf ' %q' "$@" >> "${SUB_STORE_TEST_LOG}/chown.log"
printf '\n' >> "${SUB_STORE_TEST_LOG}/chown.log"
EOF

  chmod +x "${FAKE_BIN}/systemctl" "${FAKE_BIN}/git" "${FAKE_BIN}/pnpm" \
    "${FAKE_BIN}/node" "${FAKE_BIN}/npm" "${FAKE_BIN}/curl" \
    "${FAKE_BIN}/id" "${FAKE_BIN}/useradd" "${FAKE_BIN}/chown"
}

assert_file() {
  [[ -f "$1" ]] || fail "缺少文件：$1"
}

assert_missing() {
  [[ ! -e "$1" ]] || fail "不应继续存在：$1"
}

assert_contains() {
  local needle="$1"
  local file="$2"
  grep -Fq -- "$needle" "$file" || fail "${file} 缺少内容：${needle}"
}

assert_not_contains() {
  local needle="$1"
  local file="$2"
  if grep -Fq -- "$needle" "$file"; then
    fail "${file} 不应包含内容：${needle}"
  fi
}

run_installer() {
  bash /work/install_sub_store.sh "$@"
}

write_fake_commands

SERVICE_NAME="sub-store-it"
INSTALL_DIR="${TEST_ROOT}/install"
DATA_DIR="${TEST_ROOT}/data"
BACKUP_DIR="${TEST_ROOT}/backups"
ENV_FILE="/etc/sub-store/${SERVICE_NAME}.env"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
TIMER_FILE="/etc/systemd/system/sub-store-local-backup@${SERVICE_NAME}.timer"
COMMON_ARGS=(
  --service-name "$SERVICE_NAME"
  --install-dir "$INSTALL_DIR"
  --data-dir "$DATA_DIR"
  --backup-dir "$BACKUP_DIR"
)

log "测试安装"
run_installer install --non-interactive --yes --skip-deps --no-start \
  "${COMMON_ARGS[@]}" \
  --listen 127.0.0.1 \
  --port 3199 \
  --api-url /it-path \
  --cors https://example.test \
  --local-backup-cron hourly \
  --backup-keep 3 \
  --webdav-url http://webdav.test/dav \
  --webdav-user tester \
  --webdav-password dav-password-value \
  --webdav-path /substore-it \
  --webdav-keep 2 \
  --no-backup \
  --env SUB_STORE_MAX_HEADER_SIZE=65536

assert_file "${INSTALL_DIR}/Sub-Store/backend/dist/sub-store.bundle.js"
assert_file "${INSTALL_DIR}/Sub-Store-Front-End/dist/index.html"
assert_file "${INSTALL_DIR}/Sub-Store-Front-End/.env.production"
assert_file "$ENV_FILE"
assert_file "$SERVICE_FILE"
assert_file "$TIMER_FILE"
assert_contains 'VITE_API_URL=/it-path' "${INSTALL_DIR}/Sub-Store-Front-End/.env.production"
assert_contains 'SUB_STORE_BACKEND_API_HOST="127.0.0.1"' "$ENV_FILE"
assert_contains 'SUB_STORE_BACKEND_API_PORT="3199"' "$ENV_FILE"
assert_contains 'SUB_STORE_FRONTEND_BACKEND_PATH="/it-path"' "$ENV_FILE"
assert_contains 'SUB_STORE_WEBDAV_URL="http://webdav.test/dav"' "$ENV_FILE"
assert_contains 'SUB_STORE_MAX_HEADER_SIZE="65536"' "$ENV_FILE"
assert_contains 'OnCalendar=hourly' "$TIMER_FILE"

log "测试显示状态、启动、重启、停止、关闭"
run_installer status --non-interactive --yes "${COMMON_ARGS[@]}"
run_installer start --non-interactive --yes "${COMMON_ARGS[@]}"
run_installer restart --non-interactive --yes "${COMMON_ARGS[@]}"
run_installer stop --non-interactive --yes "${COMMON_ARGS[@]}"
run_installer disable --non-interactive --yes "${COMMON_ARGS[@]}"
assert_contains 'enable --now sub-store-it.service' "${TEST_LOG}/systemctl.log"
assert_contains 'restart sub-store-it.service' "${TEST_LOG}/systemctl.log"
assert_contains 'stop sub-store-it.service' "${TEST_LOG}/systemctl.log"
assert_contains 'disable --now sub-store-it.service' "${TEST_LOG}/systemctl.log"

log "测试查看配置脱敏"
show_output="${TEST_ROOT}/show.out"
run_installer show --non-interactive --yes "${COMMON_ARGS[@]}" > "$show_output" 2>&1
assert_contains '***已隐藏，使用 --show-secrets 可查看***' "$show_output"
assert_not_contains 'dav-password-value' "$show_output"

log "测试 WebDAV 连接和备份上传"
printf 'webdav-backup-data\n' > "${DATA_DIR}/state.txt"
run_installer webdav-test --non-interactive --yes "${COMMON_ARGS[@]}"
run_installer backup --non-interactive --yes "${COMMON_ARGS[@]}" --backup-reason webdav
assert_contains 'method=MKCOL' "${TEST_LOG}/curl.log"
assert_contains 'method=PROPFIND' "${TEST_LOG}/curl.log"
assert_contains 'upload=' "${TEST_LOG}/curl.log"

log "测试已安装更新"
run_installer update --non-interactive --yes --skip-deps --no-start "${COMMON_ARGS[@]}"
assert_contains 'fetch origin master --depth=1' "${TEST_LOG}/git.log"
assert_contains 'pull --ff-only origin master' "${TEST_LOG}/git.log"

log "测试修改配置"
run_installer config --non-interactive --yes --skip-deps --no-start \
  "${COMMON_ARGS[@]}" \
  --listen 0.0.0.0 \
  --port 3299 \
  --api-url /changed-path \
  --no-webdav \
  --no-local-backup \
  --no-backup
assert_contains 'SUB_STORE_BACKEND_API_HOST="0.0.0.0"' "$ENV_FILE"
assert_contains 'SUB_STORE_BACKEND_API_PORT="3299"' "$ENV_FILE"
assert_contains 'SUB_STORE_FRONTEND_BACKEND_PATH="/changed-path"' "$ENV_FILE"
assert_contains 'VITE_API_URL=/changed-path' "${INSTALL_DIR}/Sub-Store-Front-End/.env.production"
assert_not_contains 'SUB_STORE_WEBDAV_URL=' "$ENV_FILE"

log "测试本地备份、列表、清理和恢复"
printf 'restore-source\n' > "${DATA_DIR}/state.txt"
run_installer backup --non-interactive --yes "${COMMON_ARGS[@]}" --backup-reason restoretest
backup_file="$(find "$BACKUP_DIR" -maxdepth 1 -type f -name "${SERVICE_NAME}-restoretest-*.tar.gz" | sort | tail -n 1)"
[[ -n "$backup_file" ]] || fail "未找到 restoretest 备份"
printf 'restore-target\n' > "${DATA_DIR}/state.txt"
run_installer list-backups --non-interactive --yes "${COMMON_ARGS[@]}"
run_installer restore --non-interactive --yes "${COMMON_ARGS[@]}" --backup-file "$backup_file"
grep -Fq 'restore-source' "${DATA_DIR}/state.txt" || fail "恢复后的数据不正确"
run_installer backup --non-interactive --yes "${COMMON_ARGS[@]}" --backup-reason cleanup-a
sleep 1
run_installer backup --non-interactive --yes "${COMMON_ARGS[@]}" --backup-reason cleanup-b
run_installer cleanup-backups --non-interactive --yes "${COMMON_ARGS[@]}" --backup-keep 1
backup_count="$(find "$BACKUP_DIR" -maxdepth 1 -type f -name "${SERVICE_NAME}-*.tar.gz" | wc -l)"
[[ "$backup_count" -le 1 ]] || fail "清理备份后仍有 ${backup_count} 个备份"

log "测试卸载"
run_installer uninstall --non-interactive --yes "${COMMON_ARGS[@]}"
assert_missing "$ENV_FILE"
assert_missing "$SERVICE_FILE"
assert_missing "${INSTALL_DIR}/Sub-Store"
assert_missing "${INSTALL_DIR}/Sub-Store-Front-End"
assert_missing "$DATA_DIR"
assert_missing "$BACKUP_DIR"

log "所有集成测试通过"
