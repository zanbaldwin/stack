FROM "golang:1.17.5-alpine3.15" AS builder
MAINTAINER Zan Baldwin "hello@zanbaldwin.com"

COPY "./build/docker/migrate/dbenv.go" "/go/src/github.com/zanbaldwin/dbenv/main.go"
ARG MIGRATE_VERSION="v4.15.1"
RUN    apk add --no-cache --virtual .migrate-build-deps git \
    && go install -tags 'mysql' "github.com/golang-migrate/migrate/v4/cmd/migrate@${MIGRATE_VERSION}" \
    && (cd '/go/src/github.com/zanbaldwin/dbenv'; go mod init; go build -o '/sbin/dbenv')

FROM "alpine:3.15" AS development
MAINTAINER Zan Baldwin "hello@zanbaldwin.com"

# Compiles a statically-linked version of the init (PID 1) process bundled with Docker since v1.13 (API v1.25).
# Alpine uses musl instead of glibc, so it's best not to use the dynamically-linked version.
# See https://github.com/krallin/tini/issues/8#issuecomment-146135930
RUN    apk add --no-cache --virtual .tini-build-deps cmake gcc git libc-dev make \
    && git clone 'git://github.com/krallin/tini.git' '/tmp/tini' \
    && ( \
        cd '/tmp/tini'; \
        git checkout "$(git describe --tags)"; \
        export CFLAGS='-DPR_SET_CHILD_SUBREAPER=36 -DPR_GET_CHILD_SUBREAPER=37'; \
        cmake . && make; \
    ) \
    && mv '/tmp/tini/tini-static' '/tini' && chmod +x '/tini' \
    && rm -rf '/tmp/tini' \
    && apk del '.tini-build-deps'
ENTRYPOINT [ "/tini", "--" ]

RUN apk add --no-cache --virtual .migrate-runtime-deps bash mysql-client mariadb-connector-c
COPY --from="builder" "/go/bin/migrate" "/sbin/migrate"
COPY --from="builder" "/sbin/dbenv" "/sbin/dbenv"
COPY "./build/docker/migrate/entrypoint.sh" "/entrypoint.sh"
ENV DATABASE_URL "mysql://root@database/stack"
CMD [ "bash", "/entrypoint.sh" ]

FROM development AS production
MAINTAINER Zan Baldwin "hello@zanbaldwin.com"

COPY './migrations' '/migrations'
