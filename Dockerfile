# syntax=docker/dockerfile:1.7

# Follow the upstream runtime release. The plugin packages are selected below
# based on the exact runtime version, rather than npm's independently moving
# `latest` tag.
ARG OPENCLAW_BASE_IMAGE=ghcr.io/openclaw/openclaw:latest
FROM ${OPENCLAW_BASE_IMAGE}

ARG OPENCLAW_PLUGIN_NAMES="@openclaw/discord @openclaw/whatsapp"
ARG HIMALAYA_VERSION=2.0.0

ENV OPENCLAW_BAKED_PLUGIN_PACK_DIR=/opt/openclaw-plugin-packs
ENV OPENCLAW_INSTALL_BAKED_PLUGINS=1

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl ripgrep \
    && rm -rf /var/lib/apt/lists/* \
    && install -d -m 0755 -o node -g node "${OPENCLAW_BAKED_PLUGIN_PACK_DIR}"

# Himalaya is a self-contained IMAP/SMTP client.  Pin it so rebuilding this
# image never silently changes the mail client used by the poller.
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
      amd64) himalaya_target=x86_64-linux ;; \
      arm64) himalaya_target=aarch64-linux ;; \
      *) echo "Unsupported architecture: $(dpkg --print-architecture)" >&2; exit 1 ;; \
    esac; \
    curl --fail --location --silent --show-error \
      "https://github.com/pimalaya/himalaya/releases/download/v${HIMALAYA_VERSION}/himalaya.${himalaya_target}.tgz" \
      --output /tmp/himalaya.tgz; \
    tar -xzf /tmp/himalaya.tgz -C /tmp; \
    install -m 0755 /tmp/himalaya /usr/local/bin/himalaya; \
    rm -rf /tmp/himalaya /tmp/himalaya.tgz; \
    himalaya --version

USER node
WORKDIR ${OPENCLAW_BAKED_PLUGIN_PACK_DIR}

RUN set -eux; \
    # The CLI may append a Git revision in parentheses, e.g.
    # "OpenClaw 2026.8.2 (0965053)". The release version is field two.
    runtime_version="$(openclaw --version | awk 'NR == 1 { print $2 }')"; \
    case "${runtime_version}" in \
      [0-9]*.[0-9]*.[0-9]*) ;; \
      *) echo "Could not determine an OpenClaw release version" >&2; exit 1 ;; \
    esac; \
    for plugin in ${OPENCLAW_PLUGIN_NAMES}; do \
      # Choose the newest plugin package no newer than the host. Official
      # plugins declare the corresponding OpenClaw release as their minimum
      # API version, so npm's unpinned `latest` is not safe here.
      npm pack "${plugin}@<=${runtime_version}"; \
    done

USER root
COPY --chmod=0755 docker-entrypoint.sh /usr/local/bin/openclaw-shipyard-entrypoint
RUN chown -R node:node "${OPENCLAW_BAKED_PLUGIN_PACK_DIR}"

USER node
WORKDIR /app
ENTRYPOINT ["/usr/local/bin/openclaw-shipyard-entrypoint"]
