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
  log "使用 Docker 镜像 ${IMAGE} 运行真实源码构建测试"
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
mkdir -p "$FAKE_BIN" /etc/systemd/system /usr/local/bin
export PATH="${FAKE_BIN}:$PATH"

cleanup() {
  if [[ -n "${BACKEND_PID:-}" ]] && kill -0 "$BACKEND_PID" >/dev/null 2>&1; then
    kill "$BACKEND_PID" >/dev/null 2>&1 || true
    wait "$BACKEND_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

cat > "${FAKE_BIN}/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
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

SERVICE_NAME="sub-store-real"
INSTALL_DIR="${TEST_ROOT}/install"
DATA_DIR="${TEST_ROOT}/data"
BACKUP_DIR="${TEST_ROOT}/backups"
PORT="3399"
BACKEND_PATH="/real-source-path"
ENV_FILE="/etc/sub-store/${SERVICE_NAME}.env"

log "运行安装脚本，使用官方源码和真实 pnpm 构建"
bash /work/install_sub_store.sh install \
  --non-interactive \
  --yes \
  --skip-deps \
  --no-start \
  --service-name "$SERVICE_NAME" \
  --install-dir "$INSTALL_DIR" \
  --data-dir "$DATA_DIR" \
  --backup-dir "$BACKUP_DIR" \
  --listen 127.0.0.1 \
  --port "$PORT" \
  --api-url "$BACKEND_PATH" \
  --no-local-backup \
  --no-backup

[[ -f "${INSTALL_DIR}/Sub-Store/backend/dist/sub-store.bundle.js" ]] || fail "后端 bundle 不存在"
[[ -f "${INSTALL_DIR}/Sub-Store-Front-End/dist/index.html" ]] || fail "前端 dist 不存在"
grep -Fq "VITE_API_URL=${BACKEND_PATH}" "${INSTALL_DIR}/Sub-Store-Front-End/.env.production" || fail "前端 VITE_API_URL 未写入"
grep -Fq "SUB_STORE_FRONTEND_BACKEND_PATH=\"${BACKEND_PATH}\"" "$ENV_FILE" || fail "后端路径前缀未写入环境文件"

log "启动真实后端 bundle 并检查监听"
set -a
. "$ENV_FILE"
set +a
node "${INSTALL_DIR}/Sub-Store/backend/dist/sub-store.bundle.js" > "${TEST_ROOT}/backend.log" 2>&1 &
BACKEND_PID="$!"

ready=0
for _ in $(seq 1 90); do
  if (echo >/dev/tcp/127.0.0.1/"$PORT") >/dev/null 2>&1; then
    ready=1
    break
  fi
  if ! kill -0 "$BACKEND_PID" >/dev/null 2>&1; then
    sed -n '1,220p' "${TEST_ROOT}/backend.log" >&2 || true
    fail "后端进程提前退出"
  fi
  sleep 1
done

[[ "$ready" -eq 1 ]] || {
  sed -n '1,220p' "${TEST_ROOT}/backend.log" >&2 || true
  fail "后端未在 ${PORT} 端口监听"
}

root_code="$(curl -sS -o "${TEST_ROOT}/root.out" -w '%{http_code}' "http://127.0.0.1:${PORT}/" || true)"
path_code="$(curl -sS -o "${TEST_ROOT}/path.out" -w '%{http_code}' "http://127.0.0.1:${PORT}${BACKEND_PATH}/" || true)"

[[ "$root_code" != "000" ]] || fail "根路径 HTTP 连接失败"
[[ "$path_code" != "000" ]] || fail "后端路径 HTTP 连接失败"

log "HTTP 根路径状态码：${root_code}"
log "HTTP 后端路径状态码：${path_code}"
log "真实源码构建和后端启动测试通过"
