ARG MYSQL_VERSION="8.0.27"

FROM "mysql:${MYSQL_VERSION}"
MAINTAINER Zan Baldwin "hello@zanbaldwin.com"

# MySQL expects the config files to have the extension ".cnf", but JetBrains
# supports syntax highlighting for ".conf" by default.
COPY "./php.conf" "/etc/mysql/conf.d/php.cnf"
COPY "./memory.conf" "/etc/mysql/conf.d/memory.cnf"
