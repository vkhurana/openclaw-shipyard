# syntax=docker/dockerfile:1.7

ARG OPENCLAW_BASE_IMAGE=ghcr.io/openclaw/openclaw:latest
FROM ${OPENCLAW_BASE_IMAGE}

ARG OPENCLAW_PLUGIN_SPECS="@openclaw/discord @openclaw/whatsapp"

ENV OPENCLAW_BAKED_PLUGIN_PACK_DIR=/opt/openclaw-plugin-packs
ENV OPENCLAW_INSTALL_BAKED_PLUGINS=1

USER root
RUN install -d -m 0755 -o node -g node "${OPENCLAW_BAKED_PLUGIN_PACK_DIR}"

USER node
WORKDIR ${OPENCLAW_BAKED_PLUGIN_PACK_DIR}

RUN set -eux; \
    for plugin in ${OPENCLAW_PLUGIN_SPECS}; do \
      npm pack "${plugin}"; \
    done

USER root
COPY --chmod=0755 docker-entrypoint.sh /usr/local/bin/openclaw-shipyard-entrypoint
RUN chown -R node:node "${OPENCLAW_BAKED_PLUGIN_PACK_DIR}"

USER node
WORKDIR /app
ENTRYPOINT ["/usr/local/bin/openclaw-shipyard-entrypoint"]
