#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${SUB_STORE_REAL_TEST_IMAGE:-node:22-bookworm}"

fail() {
  printf '真实源码测试失败：%s\n' "$*" >&2
  exit 1
}

log() {
  printf '[真实源码测试] %s\n' "$*"
}

if [[ "${SUB_STORE_REAL_TEST_INSIDE:-0}" != "1" ]]; then
  command -v docker >/dev/null 2>&1 || fail "未找到 docker"
  log "使用 Docker 镜像 ${IMAGE} 运行真实源码全功能测试"
  docker run --rm \
    -e SUB_STORE_REAL_TEST_INSIDE=1 \
    -v "${ROOT_DIR}:/work:ro" \
    -w /work \
    "${IMAGE}" \
    bash tests/real_source_smoke.sh
  exit 0
fi

TEST_ROOT="$(mktemp -d)"
FAKE_BIN="${TEST_ROOT}/fake-bin"
SYSTEMCTL_LOG="${TEST_ROOT}/systemctl.log"
WEBDAV_ROOT="${TEST_ROOT}/webdav-root"
WEBDAV_PORT="3499"
mkdir -p "$FAKE_BIN" "$WEBDAV_ROOT" /etc/systemd/system /usr/local/bin
export PATH="${FAKE_BIN}:$PATH"
export SYSTEMCTL_LOG
export WEBDAV_ROOT
export WEBDAV_PORT

cleanup() {
  if [[ -n "${BACKEND_PID:-}" ]] && kill -0 "$BACKEND_PID" >/dev/null 2>&1; then
    kill "$BACKEND_PID" >/dev/null 2>&1 || true
    wait "$BACKEND_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "${WEBDAV_PID:-}" ]] && kill -0 "$WEBDAV_PID" >/dev/null 2>&1; then
    kill "$WEBDAV_PID" >/dev/null 2>&1 || true
    wait "$WEBDAV_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

cat > "${FAKE_BIN}/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'systemctl' >> "$SYSTEMCTL_LOG"
printf ' %q' "$@" >> "$SYSTEMCTL_LOG"
printf '\n' >> "$SYSTEMCTL_LOG"
if [[ "$*" == *status* ]]; then
  printf 'fake systemd status: active\n'
fi
exit 0
EOF
chmod +x "${FAKE_BIN}/systemctl"

if ! command -v git >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  log "安装容器内基础依赖"
  apt-get update
  apt-get install -y ca-certificates curl git build-essential
fi

cat > "${TEST_ROOT}/webdav-server.js" <<'EOF'
const fs = require('fs');
const http = require('http');
const path = require('path');

const root = process.env.WEBDAV_ROOT;
const port = Number(process.env.WEBDAV_PORT || 3499);

function safePath(url) {
  const pathname = decodeURIComponent(new URL(url, `http://127.0.0.1:${port}`).pathname);
  const target = path.normalize(path.join(root, pathname));
  if (!target.startsWith(root)) throw new Error('invalid path');
  return target;
}

function hrefs(dir, prefix) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir).map((name) => `${prefix.replace(/\/$/, '')}/${encodeURIComponent(name)}`);
}

http.createServer((req, res) => {
  let target;
  try {
    target = safePath(req.url);
  } catch {
    res.writeHead(400);
    res.end();
    return;
  }

  if (req.method === 'MKCOL') {
    fs.mkdirSync(target, { recursive: true });
    res.writeHead(201);
    res.end();
    return;
  }

  if (req.method === 'PUT') {
    fs.mkdirSync(path.dirname(target), { recursive: true });
    const stream = fs.createWriteStream(target);
    req.pipe(stream);
    stream.on('finish', () => {
      res.writeHead(201);
      res.end();
    });
    return;
  }

  if (req.method === 'DELETE') {
    fs.rmSync(target, { force: true, recursive: true });
    res.writeHead(204);
    res.end();
    return;
  }

  if (req.method === 'PROPFIND') {
    fs.mkdirSync(target, { recursive: true });
    const base = new URL(req.url, `http://127.0.0.1:${port}`).pathname;
    const entries = [`${base.replace(/\/?$/, '/')}`, ...hrefs(target, base)];
    res.writeHead(207, { 'Content-Type': 'application/xml' });
    res.end(`<?xml version="1.0"?><d:multistatus xmlns:d="DAV:">${entries
      .map((href) => `<d:response><d:href>${href}</d:href></d:response>`)
      .join('')}</d:multistatus>`);
    return;
  }

  res.writeHead(200);
  res.end('ok');
}).listen(port, '127.0.0.1');
EOF

node "${TEST_ROOT}/webdav-server.js" > "${TEST_ROOT}/webdav.log" 2>&1 &
WEBDAV_PID="$!"
for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${WEBDAV_PORT}/health" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
kill -0 "$WEBDAV_PID" >/dev/null 2>&1 || fail "WebDAV 测试服务启动失败"

SERVICE_NAME="sub-store-real"
INSTALL_DIR="${TEST_ROOT}/install"
DATA_DIR="${TEST_ROOT}/data"
BACKUP_DIR="${TEST_ROOT}/backups"
PORT="3399"
CHANGED_PORT="3400"
BACKEND_PATH="/real-source-path"
CHANGED_PATH="/real-source-changed"
ENV_FILE="/etc/sub-store/${SERVICE_NAME}.env"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
TIMER_FILE="/etc/systemd/system/sub-store-local-backup@${SERVICE_NAME}.timer"
COMMON_ARGS=(
  --service-name "$SERVICE_NAME"
  --install-dir "$INSTALL_DIR"
  --data-dir "$DATA_DIR"
  --backup-dir "$BACKUP_DIR"
)

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

start_backend() {
  local env_file="$1"
  local port="$2"
  local path_prefix="$3"

  if [[ -n "${BACKEND_PID:-}" ]] && kill -0 "$BACKEND_PID" >/dev/null 2>&1; then
    kill "$BACKEND_PID" >/dev/null 2>&1 || true
    wait "$BACKEND_PID" >/dev/null 2>&1 || true
  fi

  set -a
  . "$env_file"
  set +a
  node "${INSTALL_DIR}/Sub-Store/backend/dist/sub-store.bundle.js" > "${TEST_ROOT}/backend-${port}.log" 2>&1 &
  BACKEND_PID="$!"

  ready=0
  for _ in $(seq 1 90); do
    if (echo >/dev/tcp/127.0.0.1/"$port") >/dev/null 2>&1; then
      ready=1
      break
    fi
    if ! kill -0 "$BACKEND_PID" >/dev/null 2>&1; then
      sed -n '1,220p' "${TEST_ROOT}/backend-${port}.log" >&2 || true
      fail "后端进程提前退出"
    fi
    sleep 1
  done

  [[ "$ready" -eq 1 ]] || {
    sed -n '1,220p' "${TEST_ROOT}/backend-${port}.log" >&2 || true
    fail "后端未在 ${port} 端口监听"
  }

  root_code="$(curl -sS -o "${TEST_ROOT}/root-${port}.out" -w '%{http_code}' "http://127.0.0.1:${port}/" || true)"
  path_code="$(curl -sS -o "${TEST_ROOT}/path-${port}.out" -w '%{http_code}' "http://127.0.0.1:${port}${path_prefix}/" || true)"
  [[ "$root_code" != "000" ]] || fail "根路径 HTTP 连接失败"
  [[ "$path_code" != "000" ]] || fail "后端路径 HTTP 连接失败"
  log "HTTP ${port}/ 状态码：${root_code}"
  log "HTTP ${port}${path_prefix}/ 状态码：${path_code}"
}

run_installer() {
  bash /work/install_sub_store.sh "$@"
}

log "安装：真实 clone、真实 pnpm、真实构建"
run_installer install \
  --non-interactive \
  --yes \
  --skip-deps \
  --no-start \
  "${COMMON_ARGS[@]}" \
  --listen 127.0.0.1 \
  --port "$PORT" \
  --api-url "$BACKEND_PATH" \
  --backup-keep 5 \
  --local-backup-cron hourly \
  --webdav-url "http://127.0.0.1:${WEBDAV_PORT}/dav" \
  --webdav-user tester \
  --webdav-password dav-password-value \
  --webdav-path /substore-real \
  --webdav-keep 5 \
  --no-backup

assert_file "${INSTALL_DIR}/Sub-Store/backend/dist/sub-store.bundle.js"
assert_file "${INSTALL_DIR}/Sub-Store-Front-End/dist/index.html"
assert_file "${INSTALL_DIR}/Sub-Store-Front-End/.env.production"
assert_file "$ENV_FILE"
assert_file "$SERVICE_FILE"
assert_file "$TIMER_FILE"
assert_contains "VITE_API_URL=${BACKEND_PATH}" "${INSTALL_DIR}/Sub-Store-Front-End/.env.production"
assert_contains "SUB_STORE_FRONTEND_BACKEND_PATH=\"${BACKEND_PATH}\"" "$ENV_FILE"
assert_contains "SUB_STORE_WEBDAV_URL=\"http://127.0.0.1:${WEBDAV_PORT}/dav\"" "$ENV_FILE"
assert_contains "OnCalendar=hourly" "$TIMER_FILE"
start_backend "$ENV_FILE" "$PORT" "$BACKEND_PATH"

log "服务控制：状态、启动、重启、停止、关闭"
run_installer status --non-interactive --yes "${COMMON_ARGS[@]}"
run_installer start --non-interactive --yes "${COMMON_ARGS[@]}"
run_installer restart --non-interactive --yes "${COMMON_ARGS[@]}"
run_installer stop --non-interactive --yes "${COMMON_ARGS[@]}"
run_installer disable --non-interactive --yes "${COMMON_ARGS[@]}"
assert_contains "enable --now ${SERVICE_NAME}.service" "$SYSTEMCTL_LOG"
assert_contains "restart ${SERVICE_NAME}.service" "$SYSTEMCTL_LOG"
assert_contains "stop ${SERVICE_NAME}.service" "$SYSTEMCTL_LOG"
assert_contains "disable --now ${SERVICE_NAME}.service" "$SYSTEMCTL_LOG"

log "查看配置：确认敏感值脱敏"
show_output="${TEST_ROOT}/show.out"
run_installer show --non-interactive --yes "${COMMON_ARGS[@]}" > "$show_output" 2>&1
assert_contains "***已隐藏，使用 --show-secrets 可查看***" "$show_output"
if grep -Fq "dav-password-value" "$show_output"; then
  fail "show 输出泄露 WebDAV 密码"
fi

log "WebDAV：连接测试和真实 curl 上传"
printf 'webdav-source\n' > "${DATA_DIR}/state.txt"
run_installer webdav-test --non-interactive --yes "${COMMON_ARGS[@]}"
run_installer backup --non-interactive --yes "${COMMON_ARGS[@]}" --backup-reason webdav
uploaded_count="$(find "$WEBDAV_ROOT" -type f -name "${SERVICE_NAME}-webdav-*.tar.gz" | wc -l)"
[[ "$uploaded_count" -ge 1 ]] || fail "WebDAV 没有收到上传备份"

log "更新：真实 git fetch/pull 并重新构建"
run_installer update --non-interactive --yes --skip-deps --no-start "${COMMON_ARGS[@]}"
assert_file "${INSTALL_DIR}/Sub-Store/backend/dist/sub-store.bundle.js"
assert_file "${INSTALL_DIR}/Sub-Store-Front-End/dist/index.html"

log "修改配置：改端口和路径，并重新构建前端"
run_installer config --non-interactive --yes --skip-deps --no-start \
  "${COMMON_ARGS[@]}" \
  --listen 127.0.0.1 \
  --port "$CHANGED_PORT" \
  --api-url "$CHANGED_PATH" \
  --no-webdav \
  --no-local-backup \
  --no-backup
assert_contains "SUB_STORE_BACKEND_API_PORT=\"${CHANGED_PORT}\"" "$ENV_FILE"
assert_contains "SUB_STORE_FRONTEND_BACKEND_PATH=\"${CHANGED_PATH}\"" "$ENV_FILE"
assert_contains "VITE_API_URL=${CHANGED_PATH}" "${INSTALL_DIR}/Sub-Store-Front-End/.env.production"
start_backend "$ENV_FILE" "$CHANGED_PORT" "$CHANGED_PATH"

log "本地备份、列表、恢复、清理"
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

log "卸载：删除服务、源码、环境文件、数据和备份"
run_installer uninstall --non-interactive --yes "${COMMON_ARGS[@]}"
assert_missing "$ENV_FILE"
assert_missing "$SERVICE_FILE"
assert_missing "$TIMER_FILE"
assert_missing "${INSTALL_DIR}/Sub-Store"
assert_missing "${INSTALL_DIR}/Sub-Store-Front-End"
assert_missing "$DATA_DIR"
assert_missing "$BACKUP_DIR"

log "真实源码全功能测试通过"
