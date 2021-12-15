#!/bin/bash

function retry {
    local MAX_ATTEMPTS=$1
    shift

    local COUNT=${MAX_ATTEMPTS}
    while [ ${COUNT} -gt 0 ]; do
        eval "$*" && break
        COUNT=$((${COUNT} - 1))
        sleep 5
    done

    [ ${COUNT} -eq 0 ] && {
        echo "Retry failed [${MAX_ATTEMPTS}]: $*" >&2
        exit 1;
    }
    return 0
}

function migrate {
    eval $(dbenv "$1") || { echo "Could not parse database information from database DSN." >&2; exit 2; }
    # Retry every 5 seconds for a maximum of 18 times (90 seconds total). If MySQL
    # isn't up by then you should probably investigate.
    retry 18 mysql \
            --user=\"${DB_USER}\" \
            --password=\"${DB_PASS}\" \
            --host=\"${DB_HOST}\" \
            --port=\"${DB_PORT}\" \
            --database=\"${DB_NAME}\" \
            --execute=\"SELECT 1\"\
            >/dev/null \
        && echo "Successfully connected to database \"${DB_NAME}\" on host \"${DB_HOST}\"; proceeding to perform migrations." \
        && /sbin/migrate \
            -path '/migrations' \
            -database "mysql://${DB_USER}:${DB_PASS}@tcp(${DB_HOST}:${DB_PORT})/${DB_NAME}" \
            up
}

if [ -z "${DATABASE_URL}" ]; then
    echo "Environment variable \"DATABASE_URL\" does not appear to be set." >&2
    exit 1
fi

migrate "${DATABASE_URL}"

exit 0
