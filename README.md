# Iridoporth Backend

Iridoporth 的后端服务，使用 Zig 编写，基于本地 vendored 的 `zap` HTTP 框架构建。当前主要负责采样树莓派运行状态，并通过 HTTP API 输出给前端或其他客户端。

## 功能

- 监听 HTTP 服务，默认端口为 `3000`
- 每秒采样一次树莓派状态
- 提供 CPU 温度、CPU 使用率、内存使用率和主机名查询接口
- 可选通过 `IRIDOPORTH_PUBLIC_DIR` 托管静态文件

## 环境要求

- Zig 0.17 或兼容当前 `build.zig` 的版本
- Linux / Raspberry Pi 环境可获得完整硬件状态数据
- Docker 可选，用于容器化构建和运行

项目依赖已放在 `zig-pkg/` 下，不需要额外拉取 Zig 包。其中 `zap` 是 MIT 协议的第三方 HTTP 框架；由于上游当前尚未支持 Zig 0.17，本项目暂时 vendored 了一份并做了兼容性 patch。

## 本地运行

```sh
zig build run
```

指定端口：

```sh
IRIDOPORTH_PORT=3000 zig build run
```

指定静态文件目录：

```sh
IRIDOPORTH_PUBLIC_DIR=./public zig build run
```

## 构建

```sh
zig build
```

构建产物默认输出到：

```text
zig-out/bin/Iridoporth_backend
```

Release 构建：

```sh
zig build -Doptimize=ReleaseSafe
```

## 测试

```sh
zig build test
```

## Scripts

`scripts/install-zig-from-mirrors.sh` 用于在 Docker 构建 Zig 基础镜像时，从 Zig 官方索引和社区镜像下载并校验指定版本的 Zig。一般开发时不需要手动执行。

## API

### 获取树莓派状态

```http
GET /api/v1/raspi/status
```

示例响应：

```json
{
  "ok": true,
  "data": {
    "available": true,
    "name": "raspberrypi",
    "cpu_temperature": 48.2,
    "cpu_usage": 12.5,
    "memory_usage": 41.8
  }
}
```

当当前环境无法读取树莓派状态时：

```json
{
  "ok": true,
  "data": {
    "available": false,
    "name": null,
    "cpu_temperature": null,
    "cpu_usage": null,
    "memory_usage": null
  }
}
```

## 环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `IRIDOPORTH_PORT` | `3000` | HTTP 服务监听端口 |
| `IRIDOPORTH_PUBLIC_DIR` | 未设置 | 静态文件目录，未设置时不托管静态文件 |

## Docker

先构建项目使用的 Zig 基础镜像：

```sh
docker build -f Dockerfile.zig -t local/zig:0.17 .
```

再构建后端镜像：

```sh
docker build -t iridoporth-backend:dev .
```

运行：

```sh
docker run --rm -p 3000:3000 -e IRIDOPORTH_PORT=3000 iridoporth-backend:dev
```

如果同时运行前端和后端，可使用：

```sh
docker compose up --build
```

`docker-compose.yml` 默认假设前端项目位于同级目录 `../Iridoporth-frontend`。

## 目录结构

```text
src/
  main.zig                    # 应用入口
  context.zig                 # 应用上下文和错误处理
  endpoints/raspi_status.zig  # 树莓派状态 API
  services/raspi.zig          # 树莓派状态采样逻辑
zig-pkg/
  zap/                        # 本地 HTTP 框架依赖
```
