# ===== Этап сборки =====
FROM swift:6.0 as build

WORKDIR /build

COPY ./Package.* ./
RUN swift package resolve

COPY . .
RUN swift build -c release --static-swift-stdlib

# ===== Финальный образ =====
# ИЗМЕНЕНИЕ: Ubuntu 24.04 вместо 22.04
FROM ubuntu:24.04

RUN apt-get update -y \
    && apt-get install -y \
       ca-certificates \
       libssl3 \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --user-group --create-home --system --skel /dev/null --home-dir /app vapor

WORKDIR /app
COPY --from=build --chown=vapor:vapor /build/.build/release /app

USER vapor:vapor

ENV HOSTNAME=0.0.0.0
EXPOSE 8080

ENTRYPOINT ["./DswAggregator"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]