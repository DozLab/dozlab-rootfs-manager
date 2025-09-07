FROM golang:1.20-alpine AS build

WORKDIR /go/src/

COPY init .

RUN go build --tags netgo --ldflags '-s -w -extldflags "-lm -lstdc++ -static"' -o init main.go

FROM alpine:3.18

RUN apk add --no-cache curl ca-certificates htop

COPY --from=build /go/src/init /init

