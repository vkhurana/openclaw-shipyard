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

install_copilot_platform_package() {
  [ -n "${GITHUB_COPILOT_CLI_VERSION:-}" ] || return 0

  case "$(uname -m)" in
    x86_64) copilot_arch=x64 ;;
    aarch64|arm64) copilot_arch=arm64 ;;
    *) return 0 ;;
  esac
  if ldd --version 2>&1 | grep -qi musl; then
    copilot_platform=linuxmusl
  else
    copilot_platform=linux
  fi

  for copilot_dir in "${OPENCLAW_CONFIG_DIR}"/npm/projects/*/node_modules/@openclaw/copilot; do
    [ -d "${copilot_dir}" ] || continue
    project_dir="${copilot_dir%/node_modules/@openclaw/copilot}"
    package_name="@github/copilot-${copilot_platform}-${copilot_arch}"
    package_dir="${project_dir}/node_modules/${package_name}"
    sdk_client="${project_dir}/node_modules/@github/copilot-sdk/dist/client.js"

    # Newer SDKs no longer load the legacy platform-package SDK entrypoint.
    [ -f "${sdk_client}" ] || continue
    grep -Fq 'packageName}/sdk' "${sdk_client}" || continue
    if [ -f "${package_dir}/sdk/index.js" ]; then
      continue
    fi

    # SDK 1.0.11 requires the platform package's /sdk export, which was
    # removed in Copilot CLI 1.0.81. Extract the compatible artifact without
    # changing OpenClaw's managed plugin lockfile or peer links.
    temp_dir="$(mktemp -d)"
    npm pack --silent --pack-destination "${temp_dir}" \
      "${package_name}@${GITHUB_COPILOT_CLI_VERSION}" >/dev/null
    rm -rf "${package_dir}"
    mkdir -p "$(dirname "${package_dir}")"
    tar -xzf "${temp_dir}"/*.tgz -C "${temp_dir}"
    mv "${temp_dir}/package" "${package_dir}"
    rm -rf "${temp_dir}"
  done
}

install_baked_plugins
install_copilot_platform_package

cd /app
exec "$@"
