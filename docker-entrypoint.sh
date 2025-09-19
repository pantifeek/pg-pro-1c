#!/bin/bash
set -e

# Определяем последнюю установленную версию PostgreSQL
PG_MAJOR=$(ls -1 /usr/lib/postgresql | sort -n | tail -1)
PG_BIN="/usr/lib/postgresql/$PG_MAJOR/bin"

if [ "$1" = 'postgres' ]; then
    if [ -z "$POSTGRES_PASSWORD" ]; then
        echo "POSTGRES_PASSWORD must be set"
        exit 1
    fi

    if [ ! -s "$PGDATA/PG_VERSION" ]; then
        echo "Initializing database in $PGDATA"
        "$PG_BIN/initdb" --username=postgres --pwfile=<(echo "$POSTGRES_PASSWORD") -D "$PGDATA" --locale=ru_RU.UTF-8

        echo "listen_addresses='*'" >> "$PGDATA/postgresql.conf"
        echo "host all all all md5" >> "$PGDATA/pg_hba.conf"
    fi

    exec "$PG_BIN/postgres" -D "$PGDATA"
fi

exec "$@"