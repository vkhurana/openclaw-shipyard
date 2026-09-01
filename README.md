# openclaw-shipyard

Custom OpenClaw image based on `ghcr.io/openclaw/openclaw:latest`, with
compatible Discord and WhatsApp channel plugins baked in.

It also includes the pinned [Himalaya](https://github.com/pimalaya/himalaya)
IMAP/SMTP client (`2.0.0`). This makes email tooling available after every
container recreate; its account configuration remains outside the image.

The image resolves exact, runtime-compatible official plugin versions during `docker build`, then installs them from npm into the mounted OpenClaw config directory on startup. This preserves the trusted npm provenance required by current OpenClaw releases; normal Docker deployments bind-mount `/home/node/.openclaw`, which would otherwise hide anything installed at build time. The first startup after a plugin version changes requires npm registry access.

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

To update the bundled Himalaya release deliberately:

```sh
docker build \
  --build-arg HIMALAYA_VERSION=2.0.0 \
  -t openclaw-shipyard:latest .
```

## Email client persistence

Himalaya is available as `himalaya` in the image. Its default configuration
is `/home/node/.openclaw/himalaya/config.toml`, below the persisted OpenClaw
config mount. To use a different location, set `HIMALAYA_CONFIG`:

```yaml
environment:
  HIMALAYA_CONFIG: /home/node/.openclaw/himalaya/config.toml
```

Store the Gmail app password in a Docker secret or host-side secret command,
never in this repository, the image, or a Compose environment value. The
polling service itself should be a separate Compose service with its own
durable state volume; that lets it restart independently of the OpenClaw
gateway and prevents a gateway upgrade from losing message state.

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

The **Publish image** workflow can also be run manually with an explicit
`openclaw_base_image` and `image_tag`. This publishes a recovery image without
overwriting the normal `latest` tag. For example, use
`ghcr.io/openclaw/openclaw:2026.7.1` and `2026.7.1` to publish
`ghcr.io/<owner>/<repo>:2026.7.1` for a config written by OpenClaw `2026.7.1`.

Use that published image in place of `ghcr.io/openclaw/openclaw`.
