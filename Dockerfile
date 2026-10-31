# Docker hosts the headless server and builds native Windows/Linux games.
ARG GODOT_VERSION=4.7.2
FROM debian:bookworm-slim AS engine
ARG GODOT_VERSION
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip libstdc++6 libfontconfig1 fonts-dejavu-core \
 && rm -rf /var/lib/apt/lists/* \
 && curl --fail --location --retry 3 \
   "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
   -o /tmp/godot.zip \
 && unzip -qq /tmp/godot.zip -d /tmp \
 && install -m 0755 "/tmp/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot \
 && rm -f /tmp/godot.zip /tmp/Godot_v${GODOT_VERSION}-stable_linux.x86_64

FROM engine AS server
WORKDIR /game
COPY . /game
# Generate the class cache once; the runtime server does not open the editor.
RUN godot --headless --editor --path /game --import
EXPOSE 7777/udp
CMD ["godot", "--headless", "--path", "/game", "--", "--server"]

FROM engine AS builder
ARG GODOT_VERSION=4.7.2
RUN curl --fail --location --retry 3 \
   "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_export_templates.tpz" \
   -o /tmp/templates.tpz \
 && mkdir -p /tmp/tpl "/root/.local/share/godot/export_templates/${GODOT_VERSION}.stable" \
 && unzip -qq /tmp/templates.tpz -d /tmp/tpl \
 && cp -a /tmp/tpl/templates/. "/root/.local/share/godot/export_templates/${GODOT_VERSION}.stable/" \
 && rm -rf /tmp/tpl /tmp/templates.tpz
WORKDIR /game
COPY . /game
CMD ["bash", "tools/export.sh"]
