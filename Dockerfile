FROM local/zig:0.17 AS builder

WORKDIR /app

COPY build.zig build.zig.zon ./
COPY src ./src
COPY zig-pkg ./zig-pkg

RUN zig build -Doptimize=ReleaseSafe

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
