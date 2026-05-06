# openclaw-shipyard

Custom OpenClaw image based on `ghcr.io/openclaw/openclaw` with the Discord and WhatsApp channel plugins baked in.

The image downloads the official plugin packages during `docker build`, stores them inside the image, and installs them into the mounted OpenClaw config directory on container startup. That matters because normal Docker deployments bind-mount `/home/node/.openclaw`, which would otherwise hide anything installed there at build time.

## Build Locally

```sh
docker build -t openclaw-shipyard:latest .
```

To pin the upstream OpenClaw image:

```sh
docker build \
  --build-arg OPENCLAW_BASE_IMAGE=ghcr.io/openclaw/openclaw:latest \
  -t openclaw-shipyard:latest .
```

To change the baked plugins:

```sh
docker build \
  --build-arg 'OPENCLAW_PLUGIN_SPECS=@openclaw/discord @openclaw/whatsapp' \
  -t openclaw-shipyard:latest .
```

## Use With Compose

If you are using the upstream OpenClaw `docker-compose.yml`, point `OPENCLAW_IMAGE` at this image:

```sh
OPENCLAW_IMAGE=ghcr.io/YOUR_GITHUB_USER/openclaw-shipyard:latest docker compose up -d
```

Or update your compose service directly:

```yaml
services:
  openclaw-gateway:
    image: ghcr.io/YOUR_GITHUB_USER/openclaw-shipyard:latest
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
