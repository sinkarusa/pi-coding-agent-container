FROM golang:1.23-alpine@sha256:383395b794dffa5b53012a212365d40c8e37109a626ca30d6151c8348d380b5f AS builder
WORKDIR /build
COPY src/credential-proxy/main.go .
COPY src/credential-proxy/routes.json .
RUN go mod init credential-proxy && \
    go build -ldflags="-s -w" -o credential-proxy .

FROM alpine:3.21
RUN apk add --no-cache ca-certificates
COPY --from=builder /build/credential-proxy /credential-proxy
# routes.json lives next to the binary so loadRoutes() can find it
COPY src/credential-proxy/routes.json /routes.json
ENTRYPOINT ["/credential-proxy"]
