# syntax=docker/dockerfile:1.7

# Follow the upstream runtime release. The plugin package versions are selected
# below based on the exact runtime version, rather than npm's independently
# moving `latest` tag.
ARG OPENCLAW_BASE_IMAGE=ghcr.io/openclaw/openclaw:latest
FROM ${OPENCLAW_BASE_IMAGE}

ARG OPENCLAW_PLUGIN_NAMES="@openclaw/discord @openclaw/whatsapp"
ARG HIMALAYA_VERSION=2.0.0
ARG GH_VERSION=2.99.0

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

# Pin the GitHub CLI for the same reason as Himalaya: rebuilding must not
# silently change the tool.
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
      amd64) gh_target=linux_amd64 ;; \
      arm64) gh_target=linux_arm64 ;; \
      *) echo "Unsupported architecture: $(dpkg --print-architecture)" >&2; exit 1 ;; \
    esac; \
    curl --fail --location --silent --show-error \
      "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_${gh_target}.tar.gz" \
      --output /tmp/gh.tgz; \
    tar -xzf /tmp/gh.tgz -C /tmp; \
    install -m 0755 "/tmp/gh_${GH_VERSION}_${gh_target}/bin/gh" /usr/local/bin/gh; \
    rm -rf /tmp/gh.tgz "/tmp/gh_${GH_VERSION}_${gh_target}"; \
    gh --version

# Put gh's config (including the OAuth token in hosts.yml) under the standard
# persisted OpenClaw config mount so auth survives container recreates. A
# single env var covers both config.yml and hosts.yml, unlike XDG_BASE_HOME.
ENV GH_CONFIG_DIR=/home/node/.openclaw/gh

# Install the Codex CLI globally and point OpenClaw at it via PATH so the
# managed-binary resolver is skipped entirely.
RUN npm install -g @openai/codex@latest
ENV OPENCLAW_CODEX_APP_SERVER_BIN=codex

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
    : > plugin-specs.txt; \
    for plugin in ${OPENCLAW_PLUGIN_NAMES}; do \
      # Choose the newest plugin package no newer than the host. Official
      # plugins declare the corresponding OpenClaw release as their minimum
      # API version, so npm's unpinned `latest` is not safe here. Record the
      # resolved version for the entrypoint to install from the official npm
      # registry, which OpenClaw recognizes as a trusted plugin source.
      npm pack --json "${plugin}@<=${runtime_version}" | node -e '\
        let output = ""; \
        process.stdin.setEncoding("utf8"); \
        process.stdin.on("data", (chunk) => { output += chunk; }); \
        process.stdin.on("end", () => { \
          const result = JSON.parse(output); \
          const packageInfo = Array.isArray(result) ? result[0] : Object.values(result)[0]; \
          const { name, version } = packageInfo; \
          if (!name || !version) process.exit(1); \
          console.log(name + "@" + version); \
        });' >> plugin-specs.txt; \
    done; \
    rm -f ./*.tgz

USER root
COPY --chmod=0755 docker-entrypoint.sh /usr/local/bin/openclaw-shipyard-entrypoint
RUN chown -R node:node "${OPENCLAW_BAKED_PLUGIN_PACK_DIR}"

USER node
WORKDIR /app
ENTRYPOINT ["/usr/local/bin/openclaw-shipyard-entrypoint"]
