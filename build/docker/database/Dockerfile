ARG MYSQL_VERSION="8.0.27"

FROM "mysql:${MYSQL_VERSION}"
MAINTAINER Zan Baldwin "hello@zanbaldwin.com"

COPY "./php.conf" "/etc/mysql/conf.d/php.conf"
COPY "./memory.conf" "/etc/mysql/conf.d/memory.conf"
