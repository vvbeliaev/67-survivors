# Multi-stage build for 67-survivors web + game server.
#
# Targets:
#   web  → nginx:alpine serving the HTML5 export at /usr/share/nginx/html
#   game → debian-slim with godot headless running the dedicated WS server
#
# Both targets share the godot-base layer, so engine + apt cache only download once.

ARG GODOT_VER=4.6.2

# --- shared base: debian + godot binary --------------------------------------
FROM debian:bookworm-slim AS godot-base
ARG GODOT_VER
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        curl ca-certificates unzip libfontconfig1 \
 && rm -rf /var/lib/apt/lists/*
RUN curl -fL --retry 6 --retry-delay 8 --retry-all-errors --connect-timeout 30 \
        "https://github.com/godotengine/godot/releases/download/${GODOT_VER}-stable/Godot_v${GODOT_VER}-stable_linux.x86_64.zip" \
        -o /tmp/godot.zip \
 && unzip -q /tmp/godot.zip -d /tmp \
 && mv "/tmp/Godot_v${GODOT_VER}-stable_linux.x86_64" /usr/local/bin/godot \
 && chmod +x /usr/local/bin/godot \
 && rm /tmp/godot.zip

# --- game: dedicated ws server -----------------------------------------------
FROM godot-base AS game
WORKDIR /app
COPY . /app
RUN godot --headless --path /app --import 2>&1 | tail -5 || true
EXPOSE 7777
CMD ["godot", "--headless", "--path", "/app", "res://src/server/server.tscn", \
     "--", "--port", "7777", "--transport", "ws", "--bind", "0.0.0.0"]

# --- web-builder: godot + export templates → /out/index.html ------------------
FROM godot-base AS web-builder
ARG GODOT_VER
RUN curl -fL --retry 6 --retry-delay 8 --retry-all-errors --connect-timeout 30 \
        "https://github.com/godotengine/godot/releases/download/${GODOT_VER}-stable/Godot_v${GODOT_VER}-stable_export_templates.tpz" \
        -o /tmp/templates.tpz \
 && mkdir -p "/root/.local/share/godot/export_templates/${GODOT_VER}.stable" \
 && unzip -q -o -j /tmp/templates.tpz "templates/*" -d "/root/.local/share/godot/export_templates/${GODOT_VER}.stable" \
 && rm /tmp/templates.tpz
WORKDIR /app
COPY . /app
RUN godot --headless --path /app --import 2>&1 | tail -5 || true
RUN mkdir -p /out && godot --headless --path /app --export-release "Web" /out/index.html

# --- web: nginx serving the export -------------------------------------------
FROM nginx:alpine AS web
COPY --from=web-builder /out /usr/share/nginx/html
COPY deploy/web.nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
