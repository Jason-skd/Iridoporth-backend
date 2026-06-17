# Iridoporth Backend

Zig 编写的 Iridoporth 后端服务，提供树莓派状态监控和 flight log 接口。HTTP 框架、SQLite 依赖均 vendored 在 `zig-pkg/`。

## 功能

- `GET /api/v1/raspi/status`：获取主机名、CPU 温度、CPU/内存使用率
- `GET /api/v1/flight-log`：列出 flight log，按最新优先返回
- `POST /api/v1/flight-log`：新增 flight log
- 可选通过 `IRIDOPORTH_PUBLIC_DIR` 托管静态文件

## 本地运行

需要 Zig 0.17 或兼容当前 `build.zig` 的版本。

```sh
zig build run
```

常用环境变量：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `IRIDOPORTH_PORT` | `3000` | HTTP 端口 |
| `IRIDOPORTH_DB_PATH` | `./data/iridoporth.db` | SQLite 数据库路径 |
| `IRIDOPORTH_PUBLIC_DIR` | 未设置 | 静态文件目录 |

## 构建与测试

```sh
zig build
zig build test
zig build -Doptimize=ReleaseSafe
```

产物位于 `zig-out/bin/Iridoporth_backend`。

## API 示例

新增 flight log：

```http
POST /api/v1/flight-log
Content-Type: application/json

{
  "content": "Hello Iridoporth",
  "callsign": "N0CALL"
}
```

`callsign` 可为 `null`。接口统一返回 JSON，成功时形如：

```json
{ "ok": true, "data": {} }
```

树莓派状态在非 Raspberry Pi/Linux 环境下可能返回 `available: false`。

## Docker

```sh
docker build -f Dockerfile.zig -t local/zig:0.17 .
docker build -t iridoporth-backend:dev .
docker run --rm -p 3000:3000 iridoporth-backend:dev
```

同时启动前后端：

```sh
docker compose up --build
```

`docker-compose.yml` 默认假设前端项目位于同级目录 `../Iridoporth-frontend`。生产部署示例见 `scripts/docker-compose.yml`。
