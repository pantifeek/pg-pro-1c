FROM ubuntu:22.04

ARG ONEC_USERNAME
ARG ONEC_PASSWORD
ARG PG_VERSION=latest

ENV ONEC_USERNAME=${ONEC_USERNAME}
ENV ONEC_PASSWORD=${ONEC_PASSWORD}

ARG DEBIAN_FRONTEND=noninteractive

# базовые утилиты
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        wget curl ca-certificates \
        bzip2 xz-utils locales gnupg lsb-release \
    && locale-gen ru_RU.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# системные зависимости, которые лучше взять из apt
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        tzdata libxml2 libldap-common libssl-dev \
        llvm-11-dev clang-11 libtcl8.6 libpython3.8 \
    && rm -rf /var/lib/apt/lists/*

# --- Определяем мажорную версию ---
# Если PG_VERSION=latest → берём последний каталог libsXX
RUN if [ "$PG_VERSION" = "latest" ]; then \
        PG_MAJOR=$(ls -1 /debs | grep -E '^libs[0-9]+' | sed 's/libs//' | sort -n | tail -1); \
    else \
        PG_MAJOR=$(echo "$PG_VERSION" | cut -d. -f1); \
    fi && \
    echo "PG_MAJOR=$PG_MAJOR" > /tmp/pg_major.env

ARG PG_MAJOR
RUN . /tmp/pg_major.env && echo "Detected PG_MAJOR=$PG_MAJOR"

# --- Копируем зависимости для этой версии ---
COPY debs/ /debs/
RUN . /tmp/pg_major.env && \
    test -d /debs/libs${PG_MAJOR} || (echo "Directory debs/libs${PG_MAJOR} not found!" && exit 1); \
    dpkg -i /debs/libs${PG_MAJOR}/*.deb || apt-get -f install -y; \
    rm -rf /var/lib/apt/lists/* /debs

ENV LANG=ru_RU.UTF-8
ENV LC_ALL=ru_RU.UTF-8
ENV PGDATA=/var/lib/postgresql/data

# Ставим OneGet и качаем пакеты
RUN set -eux; \
    mkdir -p /tmp; mkdir -p /cmd; cd /cmd; \
    curl -sL http://git.io/oneget.sh -o oneget; chmod +x oneget; \
    for i in 1 2 3; do \
        ./oneget get --path /tmp/downloads/ --rename pg:deb.x64@${PG_VERSION} && break; \
        rm -rf /tmp/downloads/*.d1c; \
        sleep 5; \
    done;

# Распаковка и установка пакетов
RUN set -eux; \
    mkdir -p /tmp/pgdist; \
    echo ">>> Найденные архивы:"; \
    find /tmp/downloads -maxdepth 3 -type f -name "*.tar.bz2" -ls; \
    for f in $(find /tmp/downloads -maxdepth 3 -type f -name "*.tar.bz2"); do \
        echo ">>> Распаковываем $f"; \
        tar -xjf "$f" -C /tmp/pgdist; \
    done; \
    echo ">>> Содержимое после распаковки:"; \
    find /tmp/pgdist -maxdepth 2 -type d -ls; \
    echo ">>> DEB файлы в основной директории:"; \
    find /tmp/pgdist/postgresql-*_amd64_deb -type f -name "*.deb" -ls || true; \
    echo ">>> DEB файлы в addon директории:"; \
    find /tmp/pgdist/postgresql-*_amd64_addon_deb -type f -name "*.deb" -ls || true; \
    dpkg -i /tmp/pgdist/postgresql-*_amd64_deb/*.deb || apt-get -f install -y; \
    if ls /tmp/pgdist/postgresql-*_amd64_addon_deb/*.deb >/dev/null 2>&1; then \
        dpkg -i /tmp/pgdist/postgresql-*_amd64_addon_deb/*.deb || apt-get -f install -y; \
    else \
        echo ">>> Addon пакетов не найдено, пропускаем"; \
    fi; \
    rm -rf /var/lib/apt/lists/* /tmp/*

# Создаём каталоги как в rsyuzyov
RUN mkdir -p /var/lib/postgresql /var/run/postgresql \
 && chown -R postgres:postgres /var/lib/postgresql /var/run/postgresql

VOLUME ["/var/lib/postgresql", "/var/run/postgresql"]

COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

USER postgres
EXPOSE 5432

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["postgres"]