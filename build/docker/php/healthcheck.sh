#!/bin/sh
set -e

# Check if PHP-FPM is running on a Unix Socket.
if env -i REQUEST_METHOD='GET' SCRIPT_NAME='/ping' SCRIPT_FILENAME='/ping' cgi-fcgi -bind -connect '/var/run/php/php-fpm.sock'; then
	exit 0
fi

# Check if PHP-FPM or RoadRunner is running bound to a port.
if env -i REQUEST_METHOD='GET' SCRIPT_NAME='/ping' SCRIPT_FILENAME='/ping' cgi-fcgi -bind -connect '127.0.0.1:9000'; then
	exit 0
fi

# Check if RoadRunner's healthcheck endpoint returns a successful response.
# Check this last, it takes the longest (only by milliseconds, but still).
if [ "$(curl --output '/dev/null' --head --location --silent --write-out "%{http_code}" 'http://127.0.0.1:2114/health?plugin=http')" = "200" ]; then
    exit 0
fi

exit 1
