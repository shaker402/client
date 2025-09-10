# syntax=docker/dockerfile:1
FROM mysql:9

RUN --mount=type=secret,id=SHORESH_PASSWD \
    --mount=type=bind,source=/permissions.sql,target=/permissions.sql \
    export SHORESH_PASSWORD=$(cat /run/secrets/SHORESH_PASSWD | head -n 1) && \
    sed "s/\${SHORESH_PASSWORD}/'${SHORESH_PASSWORD//\'/\'\'}'/g" /permissions.sql > /docker-entrypoint-initdb.d/00-permissions.sql
