# --- Stage 1: Build Server (Go) ---
# Wir nutzen Go 1.22-alpine für Speed und Kompatibilität mit der "toolchain" Anweisung
FROM --platform=$BUILDPLATFORM golang:1.22-alpine AS gobuild

# Notwendige Tools für den Build installieren
RUN apk add --no-cache make git bash build-base

WORKDIR /go/src/focalboard

# Quellcode direkt klonen, um "file not found" Fehler zu umgehen
RUN git clone https://github.com/mattermost/focalboard.git .

# Den Server nativ für ARM64 (Ampere) bauen
RUN cd server && \
    GOOS=linux GOARCH=arm64 go build \
    -ldflags '-X "github.com/mattermost/focalboard/server/model.BuildNumber=dev" -X "github.com/mattermost/focalboard/server/model.Edition=linux"' \
    -tags 'json1 sqlite3' \
    -o ../bin/docker/focalboard-server ./main

# --- Stage 2: Build Webapp (Node) ---
FROM --platform=$BUILDPLATFORM node:18-alpine AS nodebuild

WORKDIR /webapp
# Wir kopieren den Webapp-Quellcode aus der ersten Stage
COPY --from=gobuild /go/src/focalboard/webapp .

# Abhängigkeiten installieren und Frontend bauen (DSR: schnell & effizient)
RUN npm install --frozen-lockfile && npm run pack

# --- Stage 3: Final Runtime (Minimal Image) ---
FROM alpine:3.19

# Metadaten für dein DSR-System
LABEL maintainer="DSR-Digital-Solutions"
LABEL description="Focalboard optimized for Ampere ARM64"

WORKDIR /opt/focalboard

# Nur die fertigen Binaries und Assets kopieren (macht das Image sehr leicht)
COPY --from=gobuild /go/src/focalboard/bin/docker/focalboard-server /opt/focalboard/bin/focalboard-server
COPY --from=nodebuild /webapp/pack /opt/focalboard/pack

# Standard-Konfiguration erzeugen
RUN echo '{"serverRoot": "http://localhost:8000", "port": 8000, "dbtype": "postgres", "dbconfig": "", "useSSL": false}' > /opt/focalboard/config.json

# Berechtigungen setzen (Sicherheit)
RUN chmod +x /opt/focalboard/bin/focalboard-server

EXPOSE 8000
CMD ["/opt/focalboard/bin/focalboard-server"]
