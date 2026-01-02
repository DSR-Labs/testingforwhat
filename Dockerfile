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
RUN apk add --no-cache python3 make g++ autoconf automake libtool nasm libpng-dev zlib-dev
WORKDIR /webapp
COPY --from=gobuild /go/src/focalboard/webapp .

# ARM64 Fix: Problematische Grafik-Libs entfernen
RUN sed -i '/optipng-bin/d' package.json && \
    sed -i '/gifsicle/d' package.json && \
    sed -i '/jpegtran-bin/d' package.json

ENV SKIP_PRE_BUILD=1
ENV ADRENO_SKIP_OPTIMIZATION=true
RUN npm install --frozen-lockfile --ignore-scripts && npm run pack

# --- Stage 3: Final Runtime (Clean & Lean) ---
FROM alpine:3.19
WORKDIR /opt/focalboard

# Binaries und Web-Assets kopieren
COPY --from=gobuild /go/src/focalboard/bin/docker/focalboard-server /opt/focalboard/bin/focalboard-server
COPY --from=nodebuild /webapp/pack /opt/focalboard/pack

# Verzeichnisse für Daten und Dateien erstellen
RUN mkdir -p /opt/focalboard/data /opt/focalboard/files
RUN chmod +x /opt/focalboard/bin/focalboard-server

# KEINE config.json mehr hier – wir erzwingen Environment Variables!

EXPOSE 8000
CMD ["/opt/focalboard/bin/focalboard-server"]
