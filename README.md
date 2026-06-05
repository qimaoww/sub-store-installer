# Sub-Store 源码安装脚本

用于在 systemd Linux 服务器上从源码安装 Sub-Store 前端和后端的安装脚本。

脚本会克隆官方源码仓库、构建前后端、生成 systemd 服务，并按 Sub-Store 官方环境变量写入运行配置。

## 安装

交互式安装：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/qimaoww/sub-store-installer/main/install_sub_store.sh)
```

菜单包含：

- 安装与更新：安装 Sub-Store、更新已安装版本
- 配置与查看：修改配置、查看配置
- 备份与恢复：立即备份、恢复、查看备份、清理备份、测试 WebDAV
- 服务控制：状态、启动、重启、停止、关闭
- 卸载 Sub-Store

带参数安装：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/qimaoww/sub-store-installer/main/install_sub_store.sh) install \
  --listen 0.0.0.0 \
  --port 3000 \
  --api-url http://你的域名或IP:3000/backend
```

非交互安装：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/qimaoww/sub-store-installer/main/install_sub_store.sh) install \
  --non-interactive \
  --yes \
  --listen 0.0.0.0 \
  --port 3000 \
  --api-url http://你的域名或IP:3000/backend
```

只输入后端路径前缀时，脚本会把前端 API 地址写成相对路径，适合同源部署/反代：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/qimaoww/sub-store-installer/main/install_sub_store.sh) install \
  --listen 127.0.0.1 \
  --port 3000 \
  --api-url /你的随机后端路径
```

这种写法会生成：

```text
SUB_STORE_FRONTEND_BACKEND_PATH=/你的随机后端路径
VITE_API_URL=/你的随机后端路径
```

真实后端路径只会在你运行脚本时写入服务器本地环境文件和前端构建配置，不会写入 README 或测试文件。备份包会保存环境文件，可能包含真实路径或 Token，请只保存在可信机器上。

安装时后端路径前缀默认会随机生成；交互提示里直接回车使用随机路径，自己填写就是自定义路径。

卸载：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/qimaoww/sub-store-installer/main/install_sub_store.sh) uninstall
```

修改配置：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/qimaoww/sub-store-installer/main/install_sub_store.sh) config
```

更新已安装实例：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/qimaoww/sub-store-installer/main/install_sub_store.sh) update
```

本地备份/恢复：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/qimaoww/sub-store-installer/main/install_sub_store.sh) backup
bash <(curl -fsSL https://raw.githubusercontent.com/qimaoww/sub-store-installer/main/install_sub_store.sh) backups
bash <(curl -fsSL https://raw.githubusercontent.com/qimaoww/sub-store-installer/main/install_sub_store.sh) restore
bash <(curl -fsSL https://raw.githubusercontent.com/qimaoww/sub-store-installer/main/install_sub_store.sh) cleanup-backups
bash <(curl -fsSL https://raw.githubusercontent.com/qimaoww/sub-store-installer/main/install_sub_store.sh) webdav-test
```

查看配置：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/qimaoww/sub-store-installer/main/install_sub_store.sh) show
```

服务管理：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/qimaoww/sub-store-installer/main/install_sub_store.sh) status
bash <(curl -fsSL https://raw.githubusercontent.com/qimaoww/sub-store-installer/main/install_sub_store.sh) start
bash <(curl -fsSL https://raw.githubusercontent.com/qimaoww/sub-store-installer/main/install_sub_store.sh) restart
bash <(curl -fsSL https://raw.githubusercontent.com/qimaoww/sub-store-installer/main/install_sub_store.sh) stop
bash <(curl -fsSL https://raw.githubusercontent.com/qimaoww/sub-store-installer/main/install_sub_store.sh) disable
```

## 功能

- 源码部署后端：`sub-store-org/Sub-Store`
- 源码部署前端：`sub-store-org/Sub-Store-Front-End`
- 自定义后端监听地址：`SUB_STORE_BACKEND_API_HOST`
- 自定义后端监听端口：`SUB_STORE_BACKEND_API_PORT`
- 自定义前端访问后端地址：`VITE_API_URL`
- 前后端合并到一个 Node/systemd 服务
- 自定义 CORS 来源：`SUB_STORE_CORS_ALLOWED_ORIGINS`
- 自定义数据目录：`SUB_STORE_DATA_BASE_PATH`
- 官方 Gist 自动上传/下载备份 cron
- 脚本本地 tar.gz 备份、恢复、查看、清理
- systemd timer 本地自动备份
- WebDAV 远程备份上传和连接测试
- 已安装实例更新，更新前默认自动本地备份
- 官方同步、产物生成、启动恢复等高级环境变量
- 支持 `--env SUB_STORE_*=...` 追加官方环境变量

## 快速使用

```bash
sudo bash install_sub_store.sh \
  --listen 0.0.0.0 \
  --port 3000 \
  --api-url http://你的域名或IP:3000/backend
```

默认情况下：

- 前端访问地址：`http://你的域名或IP:3000/`
- 后端 API 地址：默认随机路径；自己填写 `--api-url` 或 `--frontend-backend-path` 时使用自定义路径
- systemd 服务名：`sub-store.service`
- 安装目录：`/opt/sub-store`
- 数据目录：`/opt/sub-store/data`
- 自动上传备份 cron：`0 */6 * * *`
- 本地备份目录：`/opt/sub-store/backups`
- 本地备份保留数量：`7`
- 本地自动备份 timer：`daily`

## 常用示例

绑定到本机，只允许本机访问：

```bash
sudo bash install_sub_store.sh \
  --listen 127.0.0.1 \
  --port 3000 \
  --api-url http://127.0.0.1:3000/backend
```

使用域名和 HTTPS 反代：

```bash
sudo bash install_sub_store.sh \
  --listen 127.0.0.1 \
  --port 3000 \
  --api-url https://sub.example.com/backend \
  --cors https://sub.example.com
```

关闭默认自动备份：

```bash
sudo bash install_sub_store.sh --no-backup
```

自定义自动上传备份时间：

```bash
sudo bash install_sub_store.sh \
  --backup-upload-cron "0 */12 * * *"
```

立即创建本地备份：

```bash
sudo bash install_sub_store.sh backup
```

启用 WebDAV 远程备份：

```bash
sudo bash install_sub_store.sh config \
  --webdav-url https://example.com/dav \
  --webdav-user your-user \
  --webdav-password your-app-password \
  --webdav-path /sub-store
```

测试 WebDAV 连接：

```bash
sudo bash install_sub_store.sh webdav-test
```

查看本地备份列表：

```bash
sudo bash install_sub_store.sh backups
```

从备份恢复：

```bash
sudo bash install_sub_store.sh restore
```

更新已安装实例：

```bash
sudo bash install_sub_store.sh update
```

追加官方环境变量：

```bash
sudo bash install_sub_store.sh \
  --env SUB_STORE_MAX_HEADER_SIZE=65536
```

## 参数

查看完整参数：

```bash
bash install_sub_store.sh --help
```

本地操作：

```bash
bash install_sub_store.sh install
bash install_sub_store.sh update
bash install_sub_store.sh backup
bash install_sub_store.sh restore
bash install_sub_store.sh backups
bash install_sub_store.sh cleanup-backups
bash install_sub_store.sh webdav-test
bash install_sub_store.sh uninstall
bash install_sub_store.sh config
bash install_sub_store.sh show
bash install_sub_store.sh status
bash install_sub_store.sh start
bash install_sub_store.sh restart
bash install_sub_store.sh stop
bash install_sub_store.sh disable
```

核心参数：

- `--listen HOST`：后端监听地址，默认 `0.0.0.0`
- `--port PORT`：后端监听端口，默认 `3000`
- `--api-url URL`：写入前端的后端访问地址，即 `VITE_API_URL`
- `--install-dir DIR`：安装目录，默认 `/opt/sub-store`
- `--data-dir DIR`：数据目录，默认 `/opt/sub-store/data`
- `--cors ORIGINS`：CORS 允许来源，默认 `*`

本地备份参数：

- `--backup-dir DIR`：本地备份目录，默认 `/opt/sub-store/backups`
- `--backup-keep N`：保留最近 N 份本地备份，默认 `7`
- `--local-backup-cron VALUE`：systemd `OnCalendar` 时间，默认 `daily`
- `--no-local-backup`：关闭脚本本地自动备份 timer
- `--backup-file FILE`：恢复时指定备份文件
- `--no-update-backup`：更新已安装实例前不自动创建备份
- `--webdav-url URL`：WebDAV 服务地址，例如 `https://example.com/dav`
- `--webdav-user USER`：WebDAV 用户名
- `--webdav-password PASSWORD`：WebDAV 密码或应用密码
- `--webdav-path PATH`：WebDAV 远程目录，默认 `/sub-store`
- `--webdav-keep N`：WebDAV 远程保留最近 N 份备份，默认 `7`
- `--no-webdav`：关闭 WebDAV 远程备份

官方运行参数：

- `--backup-upload-cron CRON`：`SUB_STORE_BACKEND_UPLOAD_CRON`
- `--backup-download-cron CRON`：`SUB_STORE_BACKEND_DOWNLOAD_CRON`
- `--sync-cron CRON`：`SUB_STORE_BACKEND_SYNC_CRON`
- `--produce-cron CRON`：`SUB_STORE_PRODUCE_CRON`
- `--restore-data-url URL`：`SUB_STORE_DATA_URL`
- `--restore-data-url-post JS`：`SUB_STORE_DATA_URL_POST`
- `--default-proxy VALUE`：`SUB_STORE_BACKEND_DEFAULT_PROXY`
- `--push-service VALUE`：`SUB_STORE_PUSH_SERVICE`
- `--frontend-backend-path PATH`：`SUB_STORE_FRONTEND_BACKEND_PATH`，默认随机生成
- `--env KEY=VALUE`：追加 `SUB_STORE_*` 环境变量

## 自动备份说明

脚本提供三类备份：

- 本地备份：脚本创建 tar.gz 文件，保存数据目录、环境文件、systemd 服务文件和元信息。
- WebDAV 远程备份：本地备份创建成功后，使用 curl 上传到你的 WebDAV 目录。
- 官方 Gist 备份：Sub-Store 后端按官方环境变量触发上传/下载，仍需要在前端设置 GitHub Token。

本地备份默认每天通过 systemd timer 执行一次：

```text
sub-store-local-backup@sub-store.timer
```

备份文件默认保存在：

```text
/opt/sub-store/backups
```

配置 WebDAV 后，`backup` 和 systemd timer 自动备份都会先创建本地 tar.gz，再上传同名文件到远程目录。WebDAV 密码会保存在服务器本地环境文件中，`show` 默认会隐藏它。

恢复会先创建一份 `pre-restore` 当前状态备份，再覆盖数据目录并尽量恢复环境文件和服务文件。备份包里可能包含敏感配置，请不要公开分享。

使用 `show` 查看配置时，脚本默认隐藏路径前缀、Token、Secret、代理和恢复 URL 等敏感值；需要排障时可加 `--show-secrets` 显示原始环境文件。

Sub-Store 官方 Gist 备份由前端设置中的 GitHub Token 驱动。脚本默认只写入后端定时任务：

```ini
SUB_STORE_BACKEND_UPLOAD_CRON="0 */6 * * *"
```

安装后需要进入 Sub-Store 前端设置，配置 GitHub Token。未配置 token 时，定时任务会运行但无法上传备份。

`SUB_STORE_BACKEND_DOWNLOAD_CRON` 会从远端备份恢复并覆盖本地数据，默认关闭，建议只在明确需要自动恢复时启用。

## 已安装更新说明

执行：

```bash
bash install_sub_store.sh update
```

脚本会读取现有环境文件，保留监听地址、端口、路径前缀、数据目录、备份设置等配置，更新官方前后端源码并重新构建。默认更新前会创建一份 `pre-update` 本地备份。

如果只想重建文件但暂不启动服务和本地自动备份 timer，可以执行：

```bash
bash install_sub_store.sh update --no-start
```

## systemd 管理

```bash
systemctl status sub-store
journalctl -u sub-store -f
systemctl restart sub-store
```

环境文件：

```text
/etc/sub-store/sub-store.env
```

服务文件：

```text
/etc/systemd/system/sub-store.service
```

## 测试

```bash
bash -n install_sub_store.sh
bash tests/test_install_sub_store.sh
bash tests/integration_install_sub_store.sh
bash tests/real_source_smoke.sh
```

集成测试会启动临时 Docker 容器，在容器内测试安装、更新、配置、服务控制、备份、恢复、WebDAV 和卸载，不会改宿主机的 systemd。默认测试镜像是 `debian:bookworm-slim`，也可以用 `SUB_STORE_TEST_IMAGE=镜像名` 指定本机已有镜像。

真实源码测试会启动临时 Docker 容器，使用真实 `git`、真实 `pnpm` 拉取并构建官方前后端源码，再启动后端 bundle 检查监听和 HTTP 响应。默认测试镜像是 `node:22-bookworm`，也可以用 `SUB_STORE_REAL_TEST_IMAGE=镜像名` 指定。

## 官方依据

- 后端仓库：<https://github.com/sub-store-org/Sub-Store>
- 前端仓库：<https://github.com/sub-store-org/Sub-Store-Front-End>
- CORS 配置：<https://github.com/sub-store-org/Sub-Store/blob/master/config/README.md>
- 后端环境变量与 cron：<https://github.com/sub-store-org/Sub-Store/blob/master/backend/src/restful/index.js>
- 前端 API 地址：<https://github.com/sub-store-org/Sub-Store-Front-End/blob/master/.env.production>

## License

本仓库只包含安装脚本。Sub-Store 本体遵循其官方仓库的许可证。
