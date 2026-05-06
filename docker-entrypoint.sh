#!/bin/sh
set -eu

: "${OPENCLAW_CONFIG_DIR:=/home/node/.openclaw}"
: "${OPENCLAW_WORKSPACE_DIR:=${OPENCLAW_CONFIG_DIR}/workspace}"
: "${OPENCLAW_BAKED_PLUGIN_PACK_DIR:=/opt/openclaw-plugin-packs}"
: "${OPENCLAW_INSTALL_BAKED_PLUGINS:=1}"

install_baked_plugins() {
  [ "${OPENCLAW_INSTALL_BAKED_PLUGINS}" != "0" ] || return 0
  [ -d "${OPENCLAW_BAKED_PLUGIN_PACK_DIR}" ] || return 0

  set -- "${OPENCLAW_BAKED_PLUGIN_PACK_DIR}"/*.tgz
  [ -e "$1" ] || return 0

  mkdir -p "${OPENCLAW_CONFIG_DIR}" "${OPENCLAW_WORKSPACE_DIR}"

  checksum="$(
    for package in "$@"; do
      sha256sum "${package}"
    done | sha256sum | awk '{ print $1 }'
  )"
  marker="${OPENCLAW_CONFIG_DIR}/.shipyard-baked-plugins.sha256"

  if [ -f "${marker}" ] && [ "$(cat "${marker}")" = "${checksum}" ]; then
    return 0
  fi

  for package in "$@"; do
    openclaw plugins install "${package}" --force
  done

  openclaw plugins registry --refresh
  printf '%s\n' "${checksum}" > "${marker}"
}

install_baked_plugins

cd /app
exec "$@"
