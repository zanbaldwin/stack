#!/bin/sh
set -e

if (curl --fail "http://127.0.0.1:80" >/dev/null 2>&1); then
  exit 0
fi

exit 1
