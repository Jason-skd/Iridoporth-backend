# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Zig backend for **Iridoporth** — a Raspberry Pi status monitor plus a "flight log" message board with anonymous-cookie identity, likes, and admin moderation. HTTP is served by `zap`, persistence by `sqlite`. Both deps are **vendored** under `zig-pkg/` (see below).

## Build / test / run

```sh
zig build run                          # build + run locally (default Debug)
zig build                              # build only
zig build test                         # run all tests
zig build test -Dtest-filter=<name>    # run a single test by name substring
zig build -Doptimize=ReleaseSafe       # release build
zig build -Dtarget=aarch64-linux-gnu -Doptimize=ReleaseSafe   # cross-compile (raspi/linux)
```

Binary lands in `zig-out/bin/Iridoporth_backend`. The `-Dtest-filter` option is wired up in `build.zig`; VS Code's Zig plugin is already configured to use it (`zig testArgs` in `.vscode/settings.json`).

### Zig version

The toolchain is a **Zig 0.17 dev build** (`0.17.0-dev.*`). Code uses the new 0.17 APIs throughout — do not reach for pre-0.17 patterns:

- Entry point is `pub fn main(init: std.process.Init) !void` (not the legacy `pub fn main() !void`). Config and env come from `init.environ_map` / `init.io`.
- `std.Io` is threaded explicitly through call chains as `io: std.Io`. Use it for `std.Io.Timestamp.now(io, .real)` (then `.toSeconds()`), `io.sleep(.fromSeconds(n), .awake)`, `std.Io.Dir.cwd().readFile(io, path, buf)`, and `io.randomSecure(&bytes)`.
- In tests, pass `std.testing.io` for the `io` arg.
- `std.heap.DebugAllocator` is marked `// TODO: deprecated` in `main.zig` — leave the TODO until the replacement is decided.

## Dependencies are vendored

`build.zig.zon` points `.zap` and `.sqlite` at `./zig-pkg/...` (path deps), not a registry. They ship in the repo. **`zig-pkg/` must be a complete copy** — an incomplete vendor is the classic cause of "builds locally, fails in CI" (a file that exists locally but was never committed reads as missing on a clean checkout). When something under `zig-pkg/` is missing or broken, verify with `git log --all -- <path>` before assuming a `.gitignore` issue. Zap was vendored specifically to patch a memory leak.

## Architecture: strict layering

Dependency direction flows top → bottom. A feature is typically a vertical slice across these dirs:

| Dir | Role | Notes |
|---|---|---|
| `src/main.zig` | Entrypoint | loads env config, builds `Context`, spawns the raspi sampler thread, registers endpoints, listens. |
| `src/context.zig` | `Context` | The `zap.App` context type. Owns `io`, `allocator`, `raspi` status, and the `sqlite.Db`. Implements zap's `unhandledRequest` (404) and **`unhandledError`** (the central error sink — see below). |
| `src/endpoints/` | HTTP layer | `zap.Endpoint` structs (`@This()`). One struct per route prefix. `error_strategy = .raise` on every endpoint. |
| `src/api/` | DTOs | Request/response struct shapes — the JSON wire contract. Plain data, no logic. |
| `src/http/` | Cross-cutting HTTP helpers | `api_error.zig`, `response.zig`, `request_user.zig` (session/auth). |
| `src/services/` | Business logic | Orchestration; maps repository results to domain types / DTOs. |
| `src/repositories/` | Data access | All SQL lives here. Prepared statements via the vendored `sqlite` API. |
| `src/domain/` | Pure models | Domain structs + helpers (e.g. `FlightLogResponse.fromDb`, token hashing). No I/O except `std.crypto` / `io.randomSecure`. |
| `src/db/` | DB adapter | `sqlite.zig` (open + pragmas + migrate), `migrations.zig` (schema), `error.zig` (db error sets). |

Import aliases follow the layer: `*_api`, `*_service`, `*_repository`, `*_domain`, `*_http`, `api_error`/`response_http`/`request_user_http`.

### Error strategy (the most important convention)

This is the thing most likely to trip you up. **Endpoints never send error responses themselves** for expected failure cases. Instead:

1. Every endpoint sets `error_strategy = .raise`, and `App.init` sets `.default_error_strategy = .raise`. A handler `return`s an error value (or propagates one) instead of catching it.
2. The error bubbles to **`Context.unhandledError`**, which calls `http/api_error.classify(err)`:
   - errors in the `api_error.Error` set (e.g. `APIInvalidRequest`, `APINotFound`, `APIUnauthenticated`, `APIForbidden`, `APIInvalidFlightLogEntryId`, `APIFlightLogNotFound`) → mapped to a `PublicError{ status, code }` and sent as `{ "ok": false, "error": { "code": "..." } }`;
   - anything unrecognized → `internal_error` (500).
3. So to add a new HTTP-facing failure: add an `API*` variant to `api_error.Error`, add a `classify` arm with status + code, and `return APIError.APIXxx` from the endpoint. Recent commits ("add error set for each layer", "uniform to error strategy") established this — **follow it for new code**.

Each lower layer also keeps its own typed error set rather than reusing the API set: `services/*` define e.g. `LookupError.InvalidSessionToken`, `AuthorizationError.UserNotFound`; `db/error.zig` defines `MigrationError`, `InsertReturningError`. Endpoints `catch`/`switch` on these and translate to the appropriate `API*` error. Repository functions signal "row not touched" by returning `bool`, not by erroring — endpoints map `false` → `APIFlightLogNotFound`.

### Routing is hand-rolled

Zap matches by path prefix per endpoint, with no built-in path params. `endpoints/flight_log/dispatcher.zig` parses the suffix itself into a `Route` union (`base` / `entry{entry_id}` / `entry_like{entry_id}`) and dispatches to `base_path.zig`, `entry.zig`, `like.zig`. `parseRoute` distinguishes `not_found` vs `invalid_entry_id` so each maps to the right `API*` error via `RouteParseResult.strip()`. There are table-driven tests for the parser — extend them when adding routes.

### Auth & sessions

- Identity is an HTTP-only cookie `session_token` (see `http/request_user.zig`). Three entry points: `getUserIdOrNull` (read), `requireUserIdOrCreateAnonymous` (write — lazily creates an anonymous user + 91-day session on first write), `requireAdmin` (admin gate → `APIUnauthenticated`/`APIForbidden`).
- Anonymous-cookie sessions last 91 days; password-login sessions 1 day.
- Tokens are 32 random bytes (`io.randomSecure`) → hex; stored only as **SHA-256 hex** (`hashSessionToken`). Lookup is by hash.
- Passwords: argon2id (`argon2.Params.owasp_2id`) via `std.crypto.pwhash.argon2`.
- One row per `(user_id)` is enforced by `idx_user_sessions_user_id`; session validity is filtered in SQL (`revoked_at IS NULL AND expires_at > strftime('%s','now')`).
- Cookie flags currently have `secure: false`, `same_site: .Lax` with `// TODO: set to true/.Strict in production` — don't silently "fix" these without noting the production intent.

### raspi status runs on a background thread

`main.zig` calls `startDetachedStatusSampler`, which spawns a **detached thread** (`services/raspi_status.zig`) that every 1s reads `/proc/stat`, `/proc/meminfo`, `/sys/class/thermal/thermal_zone0/temp`, computes CPU% from the idle/total delta, and `store`s into `std.atomic.Value(f32)`s inside `ctx.raspi`. The `GET /api/v1/raspi/status` endpoint just `load`s the atomics — no I/O on the request path. On non-Linux (or any read failure at init) `ctx.raspi == .unavailable` and the endpoint returns `{ available: false }`. The `docker-compose.yml` backend uses `uts: "host"` so `gethostname` works inside the container.

### DB & migrations

`db/sqlite.zig`: opens with WAL, `busy_timeout=3000`, `synchronous=NORMAL`, `foreign_keys=ON`. Schema version is tracked via the `user_version` pragma; `current_schema_version = 1`. Each migration runs inside `BEGIN IMMEDIATE`/`COMMIT`. **The app refuses to start if the DB's `user_version` is newer than the code** (`DatabaseSchemaTooNew`) — never silently downgrade. To add a migration: bump `current_schema_version`, add `migrateToV<n>`, and gate it in `migrate()`. Tests use `openMigratedTestDb()` (in-memory, already migrated).

### JSON conventions

Success: `{ "ok": true, "data": { ... } }`. Error: `{ "ok": false, "error": { "code": "..." } }` (sent by `response.sendPublicError`). Request bodies parsed with `std.json.parseFromSlice(T, arena, body, .{})` — a parse failure should `return APIError.APIInvalidRequest`. Responses stringified with `response.stringifyAndSendResponse(T, arena, r, status, value)` (uses `std.json.Stringify.valueAlloc` into the per-request arena). Every endpoint receives an `arena: Allocator` — allocate per-request scratch here, not on the GPA.

## Testing conventions

Tests live inline in the relevant layer file (`repositories/*`, `services/*`, endpoint dispatchers). `src/tests.zig` is the single test root that `@import`s every module containing tests — **add new test-bearing modules there** or they won't run. DB tests use `std.testing.allocator` + an `ArenaAllocator` and `sqlite_adapter.openMigratedTestDb()`; seed with `db.execMulti(...)`.

## Environment

| Var | Default | Purpose |
|---|---|---|
| `IRIDOPORTH_PORT` | `3000` | HTTP port |
| `IRIDOPORTH_DB_PATH` | `./data/iridoporth.db` | SQLite file (`main.zig` creates `./data/`) |
| `IRIDOPORTH_PUBLIC_DIR` | unset | Optional static-file root passed to zap |

## Docker / CI

Two-stage build: `Dockerfile.zig` produces a `local/zig:0.17` builder image; `Dockerfile` uses it to cross-compile `aarch64-linux-gnu` ReleaseSafe onto `debian:bookworm-slim`. `docker compose up --build` runs backend + an alpine sidecar that just `touch`es the db file (666) on a named volume + a frontend (expected at sibling `../Iridoporth-frontend`).

CI (`.github/workflows/docker.yml`) runs on `ubuntu-24.04-arm`, builds both images, and pushes to `ghcr.io/jason-skd/iridoporth-backend` (+ a `-zig` builder) on pushes to `main` and `v*.*.*` tags. **CI does not run `zig build test`** — tests are local-only; run them before pushing.

`docs/TODO.md` tracks open architectural questions (migrate INTEGER ids to TEXT, better migration wrapper, replace deprecated `DebugAllocator`, engineering-grade error handling) — check it before redesigning anything in those areas.
