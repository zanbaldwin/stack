ARG REDIS_VERSION="6.2.6"
FROM "redis:${REDIS_VERSION}-alpine"
MAINTAINER Zan Baldwin "hello@zanbaldwin.com"

COPY './redis.conf' '/usr/local/etc/redis/redis.conf'
CMD [ "redis-server", "/usr/local/etc/redis/redis.conf" ]
