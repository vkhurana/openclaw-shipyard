#!/bin/sh
set -eu

: "${OPENCLAW_CONFIG_DIR:=/home/node/.openclaw}"
: "${OPENCLAW_WORKSPACE_DIR:=${OPENCLAW_CONFIG_DIR}/workspace}"
: "${OPENCLAW_BAKED_PLUGIN_PACK_DIR:=/opt/openclaw-plugin-packs}"
: "${OPENCLAW_INSTALL_BAKED_PLUGINS:=1}"
: "${HIMALAYA_CONFIG:=${OPENCLAW_CONFIG_DIR}/himalaya/config.toml}"
export HIMALAYA_CONFIG

# The config directory lives under the standard persisted auth/config mount.
# Credentials are deliberately not baked into the image.
mkdir -p "$(dirname "${HIMALAYA_CONFIG}")"

install_baked_plugins() {
  [ "${OPENCLAW_INSTALL_BAKED_PLUGINS}" != "0" ] || return 0
  spec_file="${OPENCLAW_BAKED_PLUGIN_PACK_DIR}/plugin-specs.txt"
  [ -s "${spec_file}" ] || return 0

  mkdir -p "${OPENCLAW_CONFIG_DIR}" "${OPENCLAW_WORKSPACE_DIR}"

  checksum="$(
    {
      # Include the install strategy so existing volumes are repaired when it changes.
      printf '%s\n' 'npm-registry-v1'
      cat "${spec_file}"
    } | sha256sum | awk '{ print $1 }'
  )"
  marker="${OPENCLAW_CONFIG_DIR}/.shipyard-baked-plugins.sha256"

  if [ -f "${marker}" ] && [ "$(cat "${marker}")" = "${checksum}" ]; then
    return 0
  fi

  while IFS= read -r package_spec; do
    [ -n "${package_spec}" ] || continue
    # Install directly from npm: local archives are considered untrusted by
    # recent OpenClaw versions and cannot access trusted runtime APIs.
    openclaw plugins install "${package_spec}" --accept-capabilities --force --pin
  done < "${spec_file}"

  openclaw plugins registry --refresh
  printf '%s\n' "${checksum}" > "${marker}"
}

install_baked_plugins

cd /app
exec "$@"
