FROM golang:1.23-alpine AS builder
WORKDIR /build
COPY src/credential-proxy/main.go .
RUN go mod init credential-proxy && \
    go build -ldflags="-s -w" -o credential-proxy .

FROM alpine:3.21
RUN apk add --no-cache ca-certificates
COPY --from=builder /build/credential-proxy /credential-proxy
ENTRYPOINT ["/credential-proxy"]
