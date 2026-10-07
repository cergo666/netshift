# shellcheck shell=ash
#
# NaiveProxy links: naive+https://user:pass@host[:port], naive+quic://..., or a
# plain https://user:pass@host[:port] (an https link with a login is a NaiveProxy
# server; a link without one is not).
#
# Two ways to carry them, the first that is possible is used:
#   1. the sing-box core has the `naive` outbound (sing-box 1.13+, built with the
#      with_naive_outbound tag and the Chromium network stack: only some builds,
#      such as the official musl ones);
#   2. the original `naive` client (klzgrad/naiveproxy, an OpenWrt build exists) runs
#      beside sing-box as a local SOCKS5 server and sing-box sends the traffic to it.
#      It works with any sing-box build. The clients are started by the
#      netshift-naive init script from a list the configuration builder writes.

NAIVE_PORT_BASE=19300
NAIVE_LIST_FILE="/tmp/netshift-naive.list"
NAIVE_RUNNING_FILE="/tmp/netshift-naive.running"
NAIVE_INIT="/etc/init.d/netshift-naive"
NAIVE_REPO="klzgrad/naiveproxy"
NAIVE_BIN="/usr/bin/naive"
NAIVE_VERSION_FILE="$NETSHIFT_STATE_DIR/naive.version"

# Does the running core carry the naive outbound?
naive_core_supported() {
    core_has_tag_strict with_naive_outbound
}

# The path of the naive client, nothing when it is not installed.
naive_binary() {
    local candidate

    for candidate in "$NAIVE_BIN" "$(command -v naive 2> /dev/null)" /usr/bin/naive /usr/bin/naiveproxy /opt/bin/naive; do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

# A new, empty list of clients: called when a configuration build starts.
naive_sidecars_reset() {
    : > "$NAIVE_LIST_FILE"
    : > "$NAIVE_LIST_FILE.urls"
    chmod 600 "$NAIVE_LIST_FILE" "$NAIVE_LIST_FILE.urls" 2> /dev/null
}

# Adds a client for a proxy URL ("https://user:pass@host:port" or "quic://...") and
# prints the local port that serves it. The same URL gets the same port again.
naive_register() {
    local proxy_url="$1"
    local line port count

    [ -f "$NAIVE_LIST_FILE" ] || naive_sidecars_reset

    line="$(grep -F -n -x -- "$proxy_url" "$NAIVE_LIST_FILE.urls" 2> /dev/null | sed -n '1p')"
    if [ -n "$line" ]; then
        printf '%s\n' "$((NAIVE_PORT_BASE + ${line%%:*} - 1))"
        return 0
    fi

    count="$(grep -c '' "$NAIVE_LIST_FILE.urls" 2> /dev/null)"
    count="${count:-0}"
    port=$((NAIVE_PORT_BASE + count))
    printf '%s\n' "$proxy_url" >> "$NAIVE_LIST_FILE.urls"
    printf '%s|%s\n' "$port" "$proxy_url" >> "$NAIVE_LIST_FILE"
    chmod 600 "$NAIVE_LIST_FILE" "$NAIVE_LIST_FILE.urls" 2> /dev/null
    printf '%s\n' "$port"
}

# Starts, restarts (the list changed) or stops the clients to match the list.
naive_sidecars_apply() {
    if [ ! -s "$NAIVE_LIST_FILE" ]; then
        naive_sidecars_stop
        return 0
    fi

    if cmp -s "$NAIVE_LIST_FILE" "$NAIVE_RUNNING_FILE" 2> /dev/null && pgrep -x naive > /dev/null 2>&1; then
        return 0
    fi

    cp "$NAIVE_LIST_FILE" "$NAIVE_RUNNING_FILE"
    chmod 600 "$NAIVE_RUNNING_FILE" 2> /dev/null
    "$NAIVE_INIT" restart > /dev/null 2>&1 || log "Could not start the NaiveProxy clients" "error"
}

naive_sidecars_stop() {
    [ -x "$NAIVE_INIT" ] && "$NAIVE_INIT" stop > /dev/null 2>&1
    rm -f "$NAIVE_RUNNING_FILE"
    return 0
}

# ── The naive client as a component (Component Manager) ───────────────────────
#
# klzgrad/naiveproxy publishes a build for every OpenWrt architecture
# (naiveproxy-<tag>-openwrt-<arch>.tar.xz, ~4 MB). The archive is .xz, which a stock
# OpenWrt cannot unpack: the xz package is installed when it is missing. GitHub gives
# the SHA-256 of every asset in the release; the download is checked against it.

# The architecture name of the release assets for this device, from DISTRIB_ARCH
# (the names the Passwall feed maps the same way).
naive_openwrt_arch() {
    local arch

    arch="$(updates_read_openwrt_release_value DISTRIB_ARCH)"
    case "$arch" in
    aarch64_cortex-a76) arch="aarch64_generic" ;;
    i386_pentium-mmx | i386_pentium4) arch="x86" ;;
    mipsel_24kc_24kf | mipsel_74kc) arch="mipsel_24kc" ;;
    riscv64_riscv64) arch="riscv64" ;;
    esac

    printf '%s\n' "$arch"
}

# The release the client is installed from: "v154.0.8037.49-4" -> "154.0.8037.49-4",
# from the file the installer writes (the binary itself does not tell its release).
naive_installed_version() {
    naive_binary > /dev/null 2>&1 || return 1
    sed -n '1p' "$NAIVE_VERSION_FILE" 2> /dev/null
}

naive_json_error() {
    jq -n -c --arg message "$1" '{success: false, message: $message}'
}

# Reads the latest release into NAIVE_RELEASE_JSON; non-zero when GitHub does not answer.
naive_fetch_release() {
    NAIVE_RELEASE_JSON="$(updates_http_get "https://api.github.com/repos/$NAIVE_REPO/releases/latest")" || return 1
    printf '%s' "$NAIVE_RELEASE_JSON" | jq -e '.tag_name' > /dev/null 2>&1
}

# Check for a newer release: {"success":true,"current_version","latest_version","status"}
naive_component_check() {
    local latest current status

    if ! naive_fetch_release; then
        naive_json_error "Could not read the latest NaiveProxy release from GitHub"
        return 1
    fi
    latest="$(printf '%s' "$NAIVE_RELEASE_JSON" | jq -r '.tag_name' | sed 's/^v//')"
    current="$(naive_installed_version)"

    if [ -z "$current" ]; then
        if naive_binary > /dev/null 2>&1; then
            # a client that was put there by hand: its release is not known
            jq -n -c --arg latest "$latest" '{success: true, current_version: "unknown", latest_version: $latest, status: "outdated"}'
        else
            jq -n -c --arg latest "$latest" '{success: true, current_version: "not installed", latest_version: $latest, status: "not_installed"}'
        fi
        return 0
    fi

    if is_min_package_version "$current" "$latest"; then
        status="latest"
    else
        status="outdated"
    fi
    jq -n -c --arg current "$current" --arg latest "$latest" --arg status "$status" \
        '{success: true, current_version: $current, latest_version: $latest, status: $status}'
}

# Makes sure `xz` can unpack the archive: installs the package when it is missing.
naive_ensure_xz() {
    command -v xz > /dev/null 2>&1 && return 0

    updates_log "xz is missing; installing it to unpack the NaiveProxy archive" "info"
    if updates_pkg_is_apk; then
        apk add xz < /dev/null > /dev/null 2>&1
    else
        opkg update < /dev/null > /dev/null 2>&1
        opkg install xz < /dev/null > /dev/null 2>&1
    fi
    command -v xz > /dev/null 2>&1
}

# Installs (or updates) the client: {"success":true,"version","message"} or an error.
naive_component_install() {
    local arch tag asset url digest dir archive extracted size_kb free_kb actual rc

    arch="$(naive_openwrt_arch)"
    if [ -z "$arch" ]; then
        naive_json_error "Could not tell the architecture of this device (DISTRIB_ARCH)"
        return 1
    fi

    if ! naive_fetch_release; then
        naive_json_error "Could not read the latest NaiveProxy release from GitHub"
        return 1
    fi
    tag="$(printf '%s' "$NAIVE_RELEASE_JSON" | jq -r '.tag_name')"
    asset="naiveproxy-$tag-openwrt-$arch.tar.xz"
    url="$(printf '%s' "$NAIVE_RELEASE_JSON" | jq -r --arg name "$asset" '[.assets[]? | select(.name == $name) | .browser_download_url] | first // empty')"
    digest="$(printf '%s' "$NAIVE_RELEASE_JSON" | jq -r --arg name "$asset" '[.assets[]? | select(.name == $name) | .digest] | first // empty')"
    if [ -z "$url" ]; then
        naive_json_error "There is no NaiveProxy build for the architecture $arch in the release $tag"
        return 1
    fi

    if ! naive_ensure_xz; then
        naive_json_error "The xz package is needed to unpack the archive and could not be installed"
        return 1
    fi

    dir="$(mktemp -d "${TMPDIR:-/tmp}/netshift-naive.XXXXXX")" || {
        naive_json_error "Could not make a temporary directory"
        return 1
    }
    archive="$dir/$asset"

    if ! updates_download_to_file "$url" "$archive"; then
        rm -rf "$dir"
        naive_json_error "Could not download $asset"
        return 1
    fi

    case "$digest" in
    sha256:*)
        actual="$(sha256sum "$archive" 2> /dev/null | awk '{print $1}' | tr 'A-F' 'a-f')"
        if [ -z "$actual" ] || [ "$actual" != "$(printf '%s' "${digest#sha256:}" | tr 'A-F' 'a-f')" ]; then
            rm -rf "$dir"
            naive_json_error "The downloaded archive does not match the checksum of the release"
            return 1
        fi
        ;;
    *) updates_log "The release gives no checksum for $asset; installing without checking it" "warn" ;;
    esac

    mkdir -p "$dir/x"
    if ! xz -dc "$archive" | tar -x -C "$dir/x" 2> /dev/null; then
        rm -rf "$dir"
        naive_json_error "Could not unpack the archive"
        return 1
    fi
    extracted="$(find "$dir/x" -type f -name naive 2> /dev/null | sed -n '1p')"
    if [ -z "$extracted" ]; then
        rm -rf "$dir"
        naive_json_error "The archive has no naive binary"
        return 1
    fi
    chmod 755 "$extracted"

    # a binary of another architecture does not even start (126/127)
    "$extracted" --version > /dev/null 2>&1
    rc=$?
    if [ "$rc" -eq 126 ] || [ "$rc" -eq 127 ]; then
        rm -rf "$dir"
        naive_json_error "The NaiveProxy binary does not run on this device"
        return 1
    fi

    size_kb="$(du -k "$extracted" 2> /dev/null | awk '{print $1}')"
    free_kb="$(df -Pk "$(dirname "$NAIVE_BIN")" 2> /dev/null | awk 'NR==2 {print $4}')"
    if [ -n "$size_kb" ] && [ -n "$free_kb" ] && [ "$free_kb" -lt $((size_kb + 1024)) ]; then
        rm -rf "$dir"
        naive_json_error "Not enough free space for the NaiveProxy client ($((size_kb / 1024)) MB needed)"
        return 1
    fi

    if ! cp "$extracted" "$NAIVE_BIN.new" || ! mv "$NAIVE_BIN.new" "$NAIVE_BIN"; then
        rm -f "$NAIVE_BIN.new"
        rm -rf "$dir"
        naive_json_error "Could not write $NAIVE_BIN"
        return 1
    fi
    chmod 755 "$NAIVE_BIN"
    mkdir -p "$(dirname "$NAIVE_VERSION_FILE")"
    printf '%s\n' "${tag#v}" > "$NAIVE_VERSION_FILE"
    rm -rf "$dir"

    # sections that were waiting for the client can be built now
    naive_component_restart_service

    jq -n -c --arg version "${tag#v}" '{success: true, version: $version, message: "NaiveProxy client installed"}'
}

# Removes the client.
naive_component_remove() {
    naive_sidecars_stop
    rm -f "$NAIVE_BIN" "$NAIVE_BIN.new" "$NAIVE_VERSION_FILE"
    naive_component_restart_service
    jq -n -c '{success: true, message: "NaiveProxy client removed"}'
}

# NetShift is restarted only when it runs, so that the links of the sections are built
# again with (or without) the client.
naive_component_restart_service() {
    if pidof sing-box > /dev/null 2>&1; then
        updates_restart_netshift
    fi
}
