# --- Stage 1: Build Server (Go) ---
FROM --platform=$BUILDPLATFORM golang:1.22-alpine AS gobuild

RUN apk add --no-cache make git bash build-base

WORKDIR /go/src/focalboard
RUN git clone https://github.com/mattermost/focalboard.git .

RUN cd server && \
    CGO_ENABLED=1 \
    CGO_CFLAGS="-D_LARGEFILE64_SOURCE" \
    GOOS=linux GOARCH=arm64 go build \
    -ldflags '-X "github.com/mattermost/focalboard/server/model.BuildNumber=dev" -X "github.com/mattermost/focalboard/server/model.Edition=linux"' \
    -tags 'json1 sqlite3' \
    -o ../bin/docker/focalboard-server ./main

# --- Stage 2: Build Webapp (Node) ---
FROM --platform=$BUILDPLATFORM node:18-alpine AS nodebuild

# FIX für ARM64: Build-Tools für node-gyp und Grafik-Libs (gifsicle, optipng, etc.) hinzufügen
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    autoconf \
    automake \
    libtool \
    nasm \
    libpng-dev \
    zlib-dev

WORKDIR /webapp
COPY --from=gobuild /go/src/focalboard/webapp .

# Installation und Build
RUN npm install --frozen-lockfile && npm run pack

# --- Stage 3: Final Runtime ---
FROM alpine:3.19
WORKDIR /opt/focalboard
COPY --from=gobuild /go/src/focalboard/bin/docker/focalboard-server /opt/focalboard/bin/focalboard-server
COPY --from=nodebuild /webapp/pack /opt/focalboard/pack
RUN echo '{"serverRoot": "http://localhost:8000", "port": 8000, "dbtype": "postgres", "dbconfig": "", "useSSL": false}' > /opt/focalboard/config.json
RUN chmod +x /opt/focalboard/bin/focalboard-server

EXPOSE 8000
CMD ["/opt/focalboard/bin/focalboard-server"]
