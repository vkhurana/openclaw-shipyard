# openclaw-shipyard

Custom OpenClaw image based on `ghcr.io/openclaw/openclaw:latest`, with
compatible Discord and WhatsApp channel plugins baked in.

The image downloads the official plugin packages during `docker build`, stores them inside the image, and installs them into the mounted OpenClaw config directory on container startup. That matters because normal Docker deployments bind-mount `/home/node/.openclaw`, which would otherwise hide anything installed there at build time.

## Build Locally

```sh
docker build -t openclaw-shipyard:latest .
```

The image follows the upstream `latest` runtime automatically. At build time,
it reads the version in that image and downloads the newest official plugin
release no newer than that runtime. This prevents npm's independently moving
`latest` plugin tag from requiring a newer plugin API.

If an existing config was written by a newer OpenClaw release than upstream
`latest` (as with `2026.7.1` while `latest` is `2026.6.34`), build or deploy a
temporary matching runtime tag until upstream catches up:

```sh
docker build \
  --build-arg OPENCLAW_BASE_IMAGE=ghcr.io/openclaw/openclaw:2026.7.1 \
  -t openclaw-shipyard:latest .
```

To change the baked plugins:

```sh
docker build \
  --build-arg 'OPENCLAW_PLUGIN_NAMES=@openclaw/discord @openclaw/whatsapp' \
  -t openclaw-shipyard:latest .
```

## Use With Compose

If you are using the upstream OpenClaw `docker-compose.yml`, point `OPENCLAW_IMAGE` at this image:

```sh
OPENCLAW_IMAGE=ghcr.io/vkhurana/openclaw-shipyard:latest docker compose up -d
```

After this release is published, refresh an existing deployment so Docker does
not keep running its previously pulled image:

```sh
docker compose pull openclaw-gateway
docker compose up -d --force-recreate openclaw-gateway
```

Or update your compose service directly:

```yaml
services:
  openclaw-gateway:
    image: ghcr.io/vkhurana/openclaw-shipyard:latest
```

The startup installer can be disabled with:

```yaml
environment:
  OPENCLAW_INSTALL_BAKED_PLUGINS: "0"
```

## Publish To GHCR

After pushing this repo to GitHub, the included workflow publishes:

- `ghcr.io/<owner>/<repo>:latest` from the default branch
- `ghcr.io/<owner>/<repo>:<git-sha>` for each build

Use that published image in place of `ghcr.io/openclaw/openclaw`.
