# -------- Stage 1: build --------
FROM swift:6.0 as build
WORKDIR /build

# копим манифесты отдельно чтобы кэшировалось resolve
COPY Package.* ./
RUN swift package resolve

# копим весь проект и собираем
COPY . .
# ВАЖНО: без --static-swift-stdlib
RUN swift build -c release

# -------- Stage 2: runtime --------
# slim = рантайм Swift без компилятора, но с Foundation/tzdata/etc.
FROM swift:6.0-slim

# создаём юзера (как раньше)
RUN useradd --user-group --create-home --system --skel /dev/null --home-dir /app vapor

WORKDIR /app

# копируем только релизные бинарники и ресурсы
COPY --from=build --chown=vapor:vapor /build/.build/release /app

USER vapor:vapor

ENV HOSTNAME=0.0.0.0
EXPOSE 8080

ENTRYPOINT ["./DswAggregator"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]