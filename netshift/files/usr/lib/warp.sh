# shellcheck shell=ash
#
# Cloudflare WARP profile generator. Cloudflare registers a free WARP device
# without any login: a key pair is made on the router, its public half is sent to
# the API, and the answer carries the peer key and the addresses of the interface.
# The result is a system WireGuard (or AmneziaWG, when its protocol handler is
# installed) interface plus a NetShift VPN section bound to it, so the usual lists
# can route through WARP. The private key goes straight into /etc/config/network
# (readable by root only) and is never printed or logged.

WARP_API="https://api.cloudflareclient.com/v0i1909051800"
WARP_API_TIMEOUT=20
WARP_ENDPOINTS="engage.cloudflareclient.com:4500 engage.cloudflareclient.com:2408 engage.cloudflareclient.com:500"
WARP_INTERFACE_DEFAULT="warp"

# One call to the API. $1 method, $2 path, $3 bearer token (optional), $4 JSON body
# (optional), $5 proxy "host:port" (optional). Prints the answer.
warp_api_call() {
    local method="$1"
    local path="$2"
    local bearer="$3"
    local body="$4"
    local proxy="$5"

    set -- -s -m "$WARP_API_TIMEOUT" -X "$method" -H "User-Agent: okhttp/3.12.1" -H "Content-Type: application/json"
    [ -z "$bearer" ] || set -- "$@" -H "Authorization: Bearer $bearer"
    [ -z "$body" ] || set -- "$@" -d "$body"
    [ -z "$proxy" ] || set -- "$@" -x "http://$proxy"
    curl "$@" "$WARP_API/$path"
}

# A new key pair: prints the private key, then the public key.
warp_keypair() {
    local output private public

    if command -v sing-box > /dev/null 2>&1; then
        output="$(sing-box generate wg-keypair 2> /dev/null)"
        private="$(printf '%s\n' "$output" | sed -n 's/^PrivateKey: //p')"
        public="$(printf '%s\n' "$output" | sed -n 's/^PublicKey: //p')"
    elif command -v wg > /dev/null 2>&1; then
        private="$(wg genkey 2> /dev/null)"
        public="$(printf '%s' "$private" | wg pubkey 2> /dev/null)"
    fi

    [ -n "$private" ] && [ -n "$public" ] || return 1
    printf '%s\n%s\n' "$private" "$public"
}

# The protocol handler of netifd that can carry the interface: "amneziawg" (it
# hides WARP better from filtering), else "wireguard"; nothing when neither is
# installed.
warp_detect_proto() {
    if [ -f /lib/netifd/proto/amneziawg.sh ]; then
        echo "amneziawg"
    elif [ -f /lib/netifd/proto/wireguard.sh ]; then
        echo "wireguard"
    fi
}

warp_valid_endpoint() {
    local endpoint="$1"
    local host="${endpoint%:*}"
    local port="${endpoint##*:}"

    [ "$host" != "$endpoint" ] || return 1
    case "$port" in
    '' | *[!0-9]*) return 1 ;;
    esac
    [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || return 1
    is_domain "$host" || is_ipv4 "$host"
}

warp_valid_interface_name() {
    case "$1" in
    '' | [!a-z]* | *[!a-z0-9_]*) return 1 ;;
    esac
    [ "${#1}" -le 15 ]
}

# Registers a device. Prints, one per line: private key, peer public key, IPv4
# address, IPv6 address. Tries the router's own route first, then the NetShift
# service proxy (the API is blocked in some places).
warp_register() {
    local keys private public body reg id token cfg proxy peer v4 v6 attempt

    keys="$(warp_keypair)" || return 1
    private="$(printf '%s\n' "$keys" | sed -n '1p')"
    public="$(printf '%s\n' "$keys" | sed -n '2p')"

    body="{\"install_id\":\"\",\"tos\":\"$(date -u +%FT%TZ)\",\"key\":\"$public\",\"fcm_token\":\"\",\"type\":\"ios\",\"locale\":\"en_US\"}"

    proxy=""
    for attempt in direct proxy; do
        if [ "$attempt" = "proxy" ]; then
            command -v get_service_proxy_address > /dev/null 2>&1 || return 2
            proxy="$(get_service_proxy_address 2> /dev/null)"
            [ -n "$proxy" ] || return 2
        fi
        reg="$(warp_api_call POST reg "" "$body" "$proxy")"
        id="$(printf '%s' "$reg" | jq -r '.result.id // empty' 2> /dev/null)"
        token="$(printf '%s' "$reg" | jq -r '.result.token // empty' 2> /dev/null)"
        [ -z "$id" ] || [ -z "$token" ] || break
    done
    [ -n "$id" ] && [ -n "$token" ] || return 2

    cfg="$(warp_api_call PATCH "reg/$id" "$token" '{"warp_enabled":true}' "$proxy")"
    peer="$(printf '%s' "$cfg" | jq -r '.result.config.peers[0].public_key // empty' 2> /dev/null)"
    v4="$(printf '%s' "$cfg" | jq -r '.result.config.interface.addresses.v4 // empty' 2> /dev/null)"
    v6="$(printf '%s' "$cfg" | jq -r '.result.config.interface.addresses.v6 // empty' 2> /dev/null)"
    [ -n "$peer" ] && [ -n "$v4" ] || return 3

    printf '%s\n%s\n%s\n%s\n' "$private" "$peer" "$v4" "$v6"
}

# Writes the interface (and its peer) into /etc/config/network.
# $1 name, $2 proto, $3 private key, $4 peer key, $5 IPv4, $6 IPv6, $7 endpoint host, $8 port
warp_write_interface() {
    local name="$1"
    local proto="$2"
    local private="$3"
    local peer_key="$4"
    local v4="$5"
    local v6="$6"
    local host="$7"
    local port="$8"
    local peer_section="${proto}_${name}"

    uci -q delete "network.$name"
    uci -q delete "network.$peer_section"

    uci set "network.$name=interface"
    uci set "network.$name.proto=$proto"
    uci set "network.$name.private_key=$private"
    uci add_list "network.$name.addresses=$v4/32"
    [ -z "$v6" ] || uci add_list "network.$name.addresses=$v6/128"
    uci set "network.$name.mtu=1280"

    if [ "$proto" = "amneziawg" ]; then
        uci set "network.$name.awg_jc=4"
        uci set "network.$name.awg_jmin=40"
        uci set "network.$name.awg_jmax=70"
        uci set "network.$name.awg_s1=0"
        uci set "network.$name.awg_s2=0"
        uci set "network.$name.awg_h1=1"
        uci set "network.$name.awg_h2=2"
        uci set "network.$name.awg_h3=3"
        uci set "network.$name.awg_h4=4"
    fi

    uci set "network.$peer_section=$peer_section"
    uci set "network.$peer_section.interface=$name"
    uci set "network.$peer_section.public_key=$peer_key"
    uci set "network.$peer_section.endpoint_host=$host"
    uci set "network.$peer_section.endpoint_port=$port"
    uci add_list "network.$peer_section.allowed_ips=0.0.0.0/0"
    uci add_list "network.$peer_section.allowed_ips=::/0"
    # NetShift binds its own outbound to the interface; a default route through
    # WARP would send the whole router there
    uci set "network.$peer_section.route_allowed_ips=0"
    uci set "network.$peer_section.persistent_keepalive=25"
    uci commit network
}

# Adds a NetShift VPN section bound to the interface (kept as it is when it exists).
warp_write_section() {
    local name="$1"

    if [ -n "$(uci -q get "netshift.$name")" ]; then
        return 0
    fi

    uci set "netshift.$name=section"
    uci set "netshift.$name.connection_type=vpn"
    uci set "netshift.$name.interface=$name"
    uci set "netshift.$name.domain_resolver_enabled=0"
    uci commit netshift
}

warp_reload_services() {
    local name="$1"

    ifup "$name" > /dev/null 2>&1 || true
    if pidof sing-box > /dev/null 2>&1; then
        /etc/init.d/netshift reload > /dev/null 2>&1 || true
    fi
}

warp_error() {
    jq -n -c --arg error "$1" --arg hint "$2" '{ok: false, error: $error, hint: (if $hint == "" then null else $hint end)}'
}

# warp_generate [endpoint] [interface] [proto]
# Registers a WARP device and sets up the interface and the section. Prints
# {"ok":true,...} or {"ok":false,"error":...}.
warp_generate() {
    local endpoint="${1:-}"
    local name="${2:-}"
    local proto="${3:-}"
    local profile private peer v4 v6 rc host port

    [ -n "$endpoint" ] || endpoint="${WARP_ENDPOINTS%% *}"
    [ -n "$name" ] || name="$WARP_INTERFACE_DEFAULT"

    warp_valid_endpoint "$endpoint" || {
        warp_error "invalid endpoint (expected host:port)" ""
        return 1
    }
    warp_valid_interface_name "$name" || {
        warp_error "invalid interface name" ""
        return 1
    }
    if [ -n "$(uci -q get "network.$name")" ]; then
        warp_error "the interface '$name' already exists" "remove it or choose another name"
        return 1
    fi

    case "$proto" in
    amneziawg | wireguard)
        [ -f "/lib/netifd/proto/$proto.sh" ] || {
            warp_error "the '$proto' protocol is not installed" ""
            return 1
        }
        ;;
    "")
        proto="$(warp_detect_proto)"
        ;;
    *)
        warp_error "unknown protocol" ""
        return 1
        ;;
    esac
    if [ -z "$proto" ]; then
        warp_error "no WireGuard support for the network interfaces" "install the wireguard-tools package (or amneziawg-tools with luci-proto-amneziawg)"
        return 1
    fi

    profile="$(warp_register)"
    rc=$?
    case "$rc" in
    0) ;;
    1)
        warp_error "could not make a key pair" "the sing-box core or wireguard-tools is needed"
        return 1
        ;;
    2)
        warp_error "Cloudflare did not answer the registration" "api.cloudflareclient.com may be blocked here: route it through a NetShift section and try again"
        return 1
        ;;
    *)
        warp_error "Cloudflare did not return the configuration" ""
        return 1
        ;;
    esac

    private="$(printf '%s\n' "$profile" | sed -n '1p')"
    peer="$(printf '%s\n' "$profile" | sed -n '2p')"
    v4="$(printf '%s\n' "$profile" | sed -n '3p')"
    v6="$(printf '%s\n' "$profile" | sed -n '4p')"
    host="${endpoint%:*}"
    port="${endpoint##*:}"

    warp_write_interface "$name" "$proto" "$private" "$peer" "$v4" "$v6" "$host" "$port"
    warp_write_section "$name"
    warp_reload_services "$name"

    jq -n -c --arg interface "$name" --arg proto "$proto" --arg endpoint "$endpoint" --arg v4 "$v4" --arg v6 "$v6" \
        '{ok: true, interface: $interface, section: $interface, proto: $proto, endpoint: $endpoint, addresses: ([$v4, $v6] | map(select(. != "")))}'
}
