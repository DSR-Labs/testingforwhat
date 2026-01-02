# --- Stage 1: Build Server (Go) ---
FROM --platform=$BUILDPLATFORM golang:1.22-alpine AS gobuild

# Notwendige Build-Tools installieren
RUN apk add --no-cache make git bash build-base

WORKDIR /go/src/focalboard

# Quellcode direkt klonen
RUN git clone https://github.com/mattermost/focalboard.git .

# Den Server nativ für ARM64 bauen mit Fix für pread64/pwrite64
RUN cd server && \
    CGO_ENABLED=1 \
    CGO_CFLAGS="-D_LARGEFILE64_SOURCE" \
    GOOS=linux GOARCH=arm64 go build \
    -ldflags '-X "github.com/mattermost/focalboard/server/model.BuildNumber=dev" -X "github.com/mattermost/focalboard/server/model.Edition=linux"' \
    -tags 'json1 sqlite3' \
    -o ../bin/docker/focalboard-server ./main

# --- Stage 2: Build Webapp (Node) ---
FROM --platform=$BUILDPLATFORM node:18-alpine AS nodebuild

WORKDIR /webapp
COPY --from=gobuild /go/src/focalboard/webapp .

# DSR-Standard: Schnell & effizient
RUN npm install --frozen-lockfile && npm run pack

# --- Stage 3: Final Runtime (Minimal Image) ---
FROM alpine:3.19

LABEL maintainer="DSR-Labs"
LABEL description="Focalboard optimized for Ampere ARM64"

WORKDIR /opt/focalboard

# Nur Binaries & Assets kopieren für ein schmales Image
COPY --from=gobuild /go/src/focalboard/bin/docker/focalboard-server /opt/focalboard/bin/focalboard-server
COPY --from=nodebuild /webapp/pack /opt/focalboard/pack

# Standard-Konfiguration erzeugen
RUN echo '{"serverRoot": "http://localhost:8000", "port": 8000, "dbtype": "postgres", "dbconfig": "", "useSSL": false}' > /opt/focalboard/config.json

# Sicherheit: Ausführrechte setzen
RUN chmod +x /opt/focalboard/bin/focalboard-server

EXPOSE 8000
CMD ["/opt/focalboard/bin/focalboard-server"]
