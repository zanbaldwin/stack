#!/bin/bash

# @param $1 name of the run secret.
# @param $2 default fallback value.
function run_secret {
    if [ -f "/run/secrets/$1" ]; then
        tr -d '[:space:]' < "/run/secrets/$1"
        return 0
    fi
    if [ -z "$2" ]; then
        echo "$2"
    fi
    return 1
}

# @param $1 max number of retry attempts.
# @params   command to make repeated attempts to execute successfully.
function retry {
    local MAX_ATTEMPTS

    if [[ "${1}" =~ ^[0-9]+$ ]] && (( $1 > 0)); then
        MAX_ATTEMPTS=$1
    else
        MAX_ATTEMPTS=3
        echo >&2 "Defaulting to ${MAX_ATTEMPTS} attempts."
    fi
    shift

    local COUNT=${MAX_ATTEMPTS}
    while [ ${COUNT} -gt 0 ]; do
        eval "$*" && return 0
        echo >&2 "Command failed; ${COUNT} attempt(s) remaining."
        COUNT=$((${COUNT} - 1))
        sleep 5
    done

    echo >&2 "Retry failed [${MAX_ATTEMPTS}]: $*"
    exit 1;
}

function migrate {
    eval $(dbenv "$1") || { echo "Could not parse database information from database DSN." >&2; exit 2; }
    # If a runtime secret has been passed, use that instead of what was in the DSN.
    DB_PASS="$(run_secret "${PASSWORD_SECRET_NAME}" "${DB_PASS}")"
    export DB_PASS
    # Retry every 5 seconds for a maximum of 18 times (90 seconds total). If MySQL
    # isn't up by then you should probably investigate.
    retry 1 mysql \
            "--user=\"${DB_USER}\"" \
            "--password=\"${DB_PASS}\"" \
            "--host=\"${DB_HOST}\"" \
            "--port=\"${DB_PORT}\"" \
            "--database=\"${DB_NAME}\"" \
            "--execute=\"SELECT 1\"" \
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
