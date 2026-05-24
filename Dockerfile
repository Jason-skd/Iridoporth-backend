# for CI/CD to use registry zig builder image
ARG ZIG_BUILDER_IMAGE=local/zig:0.17
FROM ${ZIG_BUILDER_IMAGE} AS builder

WORKDIR /app

ARG ZIG_BUILD_TARGET=aarch64-linux-gnu

COPY build.zig build.zig.zon ./
COPY src ./src
COPY zig-pkg ./zig-pkg

RUN zig build -Dtarget=${ZIG_BUILD_TARGET} -Doptimize=ReleaseSafe

FROM debian:bookworm-slim AS runtime

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /app/zig-out/bin/Iridoporth_backend /app/Iridoporth_backend

ENV IRIDOPORTH_PORT=3000

EXPOSE 3000

CMD ["/app/Iridoporth_backend"]
