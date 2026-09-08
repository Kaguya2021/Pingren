# Build stage
FROM nimlang/nim:alpine as builder

WORKDIR /app
COPY nimble.nimble ./
RUN nimble install -y --depsonly

COPY src/ ./src/
RUN nim c -d:danger -d:ssl --opt:speed -o:bin/main src/main.nim

# Runtime stage
FROM alpine:latest

RUN apk add --no-cache ca-certificates sqlite-libs libcrypto1.1 libssl1.1 2>/dev/null || apk add --no-cache ca-certificates sqlite-libs openssl

WORKDIR /app
COPY --from=builder /app/bin/main /app/bot
RUN mkdir -p /app/data

ENV DATABASE_PATH=/app/data/bot.db

CMD ["/app/bot"]
