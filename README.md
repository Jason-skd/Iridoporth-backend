# Iridoporth Backend

Iridoporth 后端服务，用 **Zig（0.17 dev）** 编写。两个职责：

1. **树莓派状态监控** —— 后台线程每秒采样 CPU 温度/使用率、内存使用率，通过 HTTP 暴露。
2. **Flight log 留言板** —— 基于匿名 cookie 身份的留言、点赞，外加 admin 审核（隐藏 / 官方回复 / 删除）。

HTTP 由 [`zap`](https://github.com/zigzap/zap) 提供，持久化用 `sqlite`，两者均 **vendored** 在 `zig-pkg/`（无需联网拉依赖）。

## 功能一览

- 树莓派状态：`GET /api/v1/raspi/status`
- Flight log：
  - `GET /api/v1/flight-log` —— 列出可见留言（最新优先，排除已删除/已隐藏）
  - `POST /api/v1/flight-log` —— 发表留言（匿名身份，首次写操作懒创建）
  - `POST` / `DELETE /api/v1/flight-log/{id}/like` —— 点赞 / 取消点赞
  - `PATCH /api/v1/flight-log/{id}` —— 唯一的修改/审核入口（删除 / 隐藏 / 官方回复）
  - `GET /api/v1/flight-log/admin` —— admin 视角的完整列表（含已删除/已隐藏）
- 账号：
  - `POST /api/v1/login` —— 邮箱+密码登录（1 天会话）
  - `PUT /api/v1/account/password` —— 修改当前账号密码
- 可选通过 `IRIDOPORTH_PUBLIC_DIR` 托管静态文件

## 快速开始

需要 Zig 0.17 dev 构建（与当前 `build.zig` 兼容的 `0.17.0-dev.*`；CI 使用 `local/zig:0.17`）。

```sh
zig build run            # 构建 + 本地运行（默认 Debug）
```

首次启动会自动建好默认 admin 账号（见下文 [身份与权限](#身份与权限)），并在 `./data/` 下创建 SQLite 文件。服务默认监听 `0.0.0.0:3000`。

## 环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `IRIDOPORTH_PORT` | `3000` | HTTP 端口 |
| `IRIDOPORTH_DB_PATH` | `./data/iridoporth.db` | SQLite 数据库路径（`main.zig` 会自动创建 `./data/`） |
| `IRIDOPORTH_PUBLIC_DIR` | 未设置 | 静态文件根目录，传给 zap |
| `IRIDOPORTH_PRODUCTION` | 未设置 | 恰为 `"true"` 时进入生产模式：会话 cookie 改为 `secure=true`、`SameSite=Strict`；其它值/未设置 = 开发模式（`secure=false`、`SameSite=Lax`，适配本地明文 HTTP） |

## API 参考

所有响应统一为 JSON。成功：`{ "ok": true, "data": { ... } }`；失败：`{ "ok": false, "error": { "code": "..." } }`。请求体用 `application/json`，解析失败一律返回 `invalid_request`（400）。

常见错误码：`invalid_request`(400)、`not_found`(404)、`unauthenticated`(401)、`invalid_credentials`(401)、`forbidden`(403)、`user_not_found`(404)、`invalid_flight_log_entry_id`(400)、`flight_log_not_found`(404)、`internal_error`(500)。

### 树莓派状态

```http
GET /api/v1/raspi/status
```

```json
{
  "ok": true,
  "data": {
    "available": true,
    "name": "raspberrypi",
    "cpu_temperature": 52.3,
    "cpu_usage": 12.5,
    "memory_usage": 38.7
  }
}
```

非 Linux / 读取失败（如本地开发机）时 `available` 为 `false`，其余字段为 `null`。采样在后台线程进行，请求路径无 I/O。

### Flight log

**列表** —— 只返回未删除且未隐藏的条目：

```http
GET /api/v1/flight-log
```

```json
{
  "ok": true,
  "data": {
    "entries": [
      {
        "id": 31,
        "content": "Hello Iridoporth",
        "response": null,
        "responded_at": null,
        "callsign": "ANON-7f3a",
        "created_at": 1750000000,
        "created_by_this_user": true,
        "likes": 3,
        "liked_by_this_user": false
      }
    ]
  }
}
```

**发表** —— 首次写操作会懒创建一个匿名用户并下发 91 天会话 cookie：

```http
POST /api/v1/flight-log
Content-Type: application/json

{ "content": "Hello Iridoporth" }
```

```json
{ "ok": true, "data": { "id": 31, "created_at": 1750000000 } }
```

正文仅含 `content`（1–300 个码点，自动 trim）。`callsign` 由服务端生成。

**点赞 / 取消点赞** —— 同一个端点，`POST` 点赞、`DELETE` 取消（幂等切换）：

```http
POST   /api/v1/flight-log/31/like
DELETE /api/v1/flight-log/31/like
```

成功均返回 `{ "ok": true, "data": {} }`。

**修改 / 审核** —— `PATCH /api/v1/flight-log/{id}` 是唯一的变更入口，请求体 **恰好设置** 下列字段之一：

```jsonc
{ "is_deleted": true }      // 创建者软删除（删除自己发的，仅 true）
{ "is_hidden": true }       // admin 隐藏   （false = 取消隐藏）
{ "response": "已收到" }     // admin 官方回复（1–300 码点，自动 trim）
{ "clear_response": true }  // admin 清除官方回复
```

零个或多个字段同时设置、或 `is_deleted:false`，均判为 `invalid_request`。权限依动作而异（见 [身份与权限](#身份与权限)）。条目不存在或无权操作时返回 `flight_log_not_found`（404）。

**管理员列表** —— 返回所有条目（含已删除/已隐藏），每条额外带 `deleted_at` / `hidden_at`，需 admin：

```http
GET /api/v1/flight-log/admin
```

### 账号

**登录** —— 校验通过后下发 1 天 `password_login` 会话 cookie：

```http
POST /api/v1/login
Content-Type: application/json

{ "email": "admin@example.com", "password": "Admin0001" }
```

```json
{ "ok": true, "data": { "success": true } }
```

邮箱或密码错误返回 `invalid_credentials`（401），不区分两者以防枚举。

**改密码** —— 需已登录的账号会话（匿名 cookie 会被拒为 `forbidden`）：

```http
PUT /api/v1/account/password
Content-Type: application/json

{ "current_password": "Admin0001", "new_password": "new-pass-1234" }
```

`current_password` 错误 → `invalid_credentials`；新密码需 8–128 位 ASCII、不含空白，否则 `invalid_request`。

## 身份与权限

身份由 HTTP-only cookie `session_token` 承载（见 `src/http/request_user.zig`）：

- **匿名 cookie 会话** —— 91 天。读操作不需要身份；**写操作**（发留言、点赞）首次会懒创建匿名用户。仅作为便利身份，非强认证。
- **账号密码会话** —— 登录后 1 天。token 是 32 字节随机数 → hex，库中只存 SHA-256，按哈希查。
- **默认 admin** —— 每次启动都会用硬编码凭据 `admin@example.com` / `Admin0001` 幂等建号；**已存在则绝不覆盖密码**，所以改完默认密码会跨重启保留。开发环境可假设它始终存在。

`PATCH` 的动作权限：

| 动作 | 字段 | 允许 |
| --- | --- | --- |
| 软删除 | `is_deleted:true` | 该条目的创建者本人（匿名或账号） |
| 隐藏 / 取消隐藏 | `is_hidden` | admin |
| 官方回复 / 清除回复 | `response` / `clear_response` | admin |

非 admin 访问 admin 接口 → `forbidden`；会话对应的用户已不存在 → `user_not_found` 并清除 cookie。

## 构建与测试

```sh
zig build                                  # 仅构建
zig build run                              # 构建 + 运行
zig build test                             # 跑全部测试
zig build test -Dtest-filter=<name>        # 按名字子串跑单个测试
zig build -Doptimize=ReleaseSafe           # Release 构建
zig build -Dtarget=aarch64-linux-gnu -Doptimize=ReleaseSafe   # 交叉编译（树莓派/Linux）
```

产物位于 `zig-out/bin/Iridoporth_backend`。`-Dtest-filter` 在 `build.zig` 中已接好；测试根是 `src/tests.zig`（新增含测试的模块要在那里 `@import`，否则不会跑）。**CI 不跑 `zig build test`**，提交前请本地跑一遍。

## Docker / 部署

两阶段构建：`Dockerfile.zig` 产出 `local/zig:0.17` 构建镜像；`Dockerfile` 用它交叉编译 `aarch64-linux-gnu` ReleaseSafe，运行于 `debian:bookworm-slim`。

```sh
# 仅后端
docker build -f Dockerfile.zig -t local/zig:0.17 .
docker build -t iridoporth-backend:dev .
docker run --rm -p 3000:3000 iridoporth-backend:dev
```

前后端一起（`docker-compose.yml` 假设前端项目在同级 `../Iridoporth-frontend`）：

```sh
docker compose up --build
```

后端容器用 `uts: "host"` 让 `gethostname` 在容器内可用；一个 alpine sidecar 负责在命名卷上 `touch` 出 666 权限的 db 文件。生产部署示例见 `scripts/docker-compose.yml`，国内装 Zig 可用 `scripts/install-zig-from-mirrors.sh`。

CI（`.github/workflows/docker.yml`，`ubuntu-24.04-arm`）在推送 `main` 或 `v*.*.*` tag 时构建并推送 `ghcr.io/jason-skd/iridoporth-backend`（及 `-zig` 构建镜像）。

## 项目结构

严格分层（依赖自上而下），`endpoints/` → `services/` → `repositories/` → `domain/`，DTO 在 `api/`，跨层 HTTP 辅助在 `http/`，DB 适配在 `db/`。详细架构与编码约定见 [`CLAUDE.md`](./CLAUDE.md)。

## 许可证

MIT，详见 [`LICENCE.md`](./LICENCE.md)。
