FROM alpine

WORKDIR /app

RUN apk add --no-cache \
    e2fsprogs-extra

COPY ./disk/ .

COPY init.sh init.sh

CMD ["/app/init.sh"]
