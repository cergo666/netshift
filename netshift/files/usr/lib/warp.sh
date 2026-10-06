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
WARP_API_HOST="api.cloudflareclient.com"
WARP_API_TIMEOUT=8
WARP_CONNECT_TIMEOUT=5
# Addresses the API has been served from (any address of the network serves the name)
WARP_API_FALLBACK_IPS="162.159.137.105 162.159.138.105"
WARP_ENDPOINTS="engage.cloudflareclient.com:4500 engage.cloudflareclient.com:2408 engage.cloudflareclient.com:500"
WARP_INTERFACE_DEFAULT="warp"
# Address ranges of the WARP endpoints; "auto" picks a fast one of them (like the
# endpoint scouting of the apps that make WARP profiles): an address that answers
# the plain-HTTP trace page, in a data centre other than the Moscow one (DME), whose
# answer comes first.
WARP_ENDPOINT_PREFIXES="188.114.96. 188.114.97. 188.114.98. 188.114.99. 162.159.192. 162.159.193. 162.159.195. 8.34.146. 8.39.214. 8.39.204. 8.6.112. 8.35.211. 8.39.125. 8.47.69."
WARP_PROBE_COUNT=40
WARP_ENDPOINT_PORT=4500
# The signature packet (a QUIC-like first packet) AmneziaWG 1.5 sends before the handshake
WARP_AWG_I1='<b 0xce000000010897a297ecc34cd6dd000044d0ec2e2e1ea2991f467ace4222129b5a098823784694b4897b9986ae0b7280135fa85e196d9ad980b150122129ce2a9379531b0fd3e871ca5fdb883c369832f730e272d7b8b74f393f9f0fa43f11e510ecb2219a52984410c204cf875585340c62238e14ad04dff382f2c200e0ee22fe743b9c6b8b043121c5710ec289f471c91ee414fca8b8be8419ae8ce7ffc53837f6ade262891895f3f4cecd31bc93ac5599e18e4f01b472362b8056c3172b513051f8322d1062997ef4a383b01706598d08d48c221d30e74c7ce000cdad36b706b1bf9b0607c32ec4b3203a4ee21ab64df336212b9758280803fcab14933b0e7ee1e04a7becce3e2633f4852585c567894a5f9efe9706a151b615856647e8b7dba69ab357b3982f554549bef9256111b2d67afde0b496f16962d4957ff654232aa9e845b61463908309cfd9de0a6abf5f425f577d7e5f6440652aa8da5f73588e82e9470f3b21b27b28c649506ae1a7f5f15b876f56abc4615f49911549b9bb39dd804fde182bd2dcec0c33bad9b138ca07d4a4a1650a2c2686acea05727e2a78962a840ae428f55627516e73c83dd8893b02358e81b524b4d99fda6df52b3a8d7a5291326e7ac9d773c5b43b8444554ef5aea104a738ed650aa979674bbed38da58ac29d87c29d387d80b526065baeb073ce65f075ccb56e47533aef357dceaa8293a523c5f6f790be90e4731123d3c6152a70576e90b4ab5bc5ead01576c68ab633ff7d36dcde2a0b2c68897e1acfc4d6483aaaeb635dd63c96b2b6a7a2bfe042f6aed82e5363aa850aace12ee3b1a93f30d8ab9537df483152a5527faca21efc9981b304f11fc95336f5b9637b174c5a0659e2b22e159a9fed4b8e93047371175b1d6d9cc8ab745f3b2281537d1c75fb9451871864efa5d184c38c185fd203de206751b92620f7c369e031d2041e152040920ac2c5ab5340bfc9d0561176abf10a147287ea90758575ac6a9f5ac9f390d0d5b23ee12af583383d994e22c0cf42383834bcd3ada1b3825a0664d8f3fb678261d57601ddf94a8a68a7c273a18c08aa99c7ad8c6c42eab67718843597ec9930457359dfdfbce024afc2dcf9348579a57d8d3490b2fa99f278f1c37d87dad9b221acd575192ffae1784f8e60ec7cee4068b6b988f0433d96d6a1b1865f4e155e9fe020279f434f3bf1bd117b717b92f6cd1cc9bea7d45978bcc3f24bda631a36910110a6ec06da35f8966c9279d130347594f13e9e07514fa370754d1424c0a1545c5070ef9fb2acd14233e8a50bfc5978b5bdf8bc1714731f798d21e2004117c61f2989dd44f0cf027b27d4019e81ed4b5c31db347c4a3a4d85048d7093cf16753d7b0d15e078f5c7a5205dc2f87e330a1f716738dce1c6180e9d02869b5546f1c4d2748f8c90d9693cba4e0079297d22fd61402dea32ff0eb69ebd65a5d0b687d87e3a8b2c42b648aa723c7c7daf37abcc4bb85caea2ee8f55bec20e913b3324ab8f5c3304f820d42ad1b9f2ffc1a3af9927136b4419e1e579ab4c2ae3c776d293d397d575df181e6cae0a4ada5d67ecea171cca3288d57c7bbdaee3befe745fb7d634f70386d873b90c4d6c6596bb65af68f9e5121e67ebf0d89d3c909ceedfb32ce9575a7758ff080724e1ab5d5f43074ecb53a479af21ed03d7b6899c36631c0166f9d47e5e1d4528a5d3d3f744029c4b1c190cbfbad06f5f83f7ad0429fa9a2719c56ffe3783460e166de2d8>'

# Resolvers asked over HTTPS by address when the router's own DNS cannot find the API
WARP_DOH_URLS="https://1.1.1.1/dns-query https://8.8.8.8/resolve"

# One call to the API. $1 method, $2 path, $3 bearer token (optional), $4 JSON body
# (optional), $5 route: "plain" (the router's own way), "ip:<address>" (the name is
# pinned to that address, which gets round a spoiled DNS), "proxy:<host:port>" (the
# NetShift service proxy) or "relay:<url>" (a reverse proxy of the API the user runs,
# used instead of the API address). Prints the answer. Every call leaves one line
# "<route> <curl exit> <http code>" in $WARP_TRACE (when set), never the token.
warp_api_call() {
    local method="$1"
    local path="$2"
    local bearer="$3"
    local body="$4"
    local route="${5:-plain}"
    local base="$WARP_API"
    local out rc http

    set -- -s -m "$WARP_API_TIMEOUT" --connect-timeout "$WARP_CONNECT_TIMEOUT" -X "$method" \
        -H "User-Agent: okhttp/3.12.1" -H "Content-Type: application/json" -w '\n%{http_code}'
    [ -z "$bearer" ] || set -- "$@" -H "Authorization: Bearer $bearer"
    [ -z "$body" ] || set -- "$@" -d "$body"
    case "$route" in
    ip:*) set -- "$@" --resolve "$WARP_API_HOST:443:${route#ip:}" ;;
    proxy:*) set -- "$@" -x "http://${route#proxy:}" ;;
    relay:*) base="${route#relay:}"; base="${base%/}" ;;
    esac

    out="$(curl "$@" "$base/$path")"
    rc=$?
    http="$(printf '%s\n' "$out" | sed -n '$p')"
    [ -z "$WARP_TRACE" ] || printf '%s %s %s\n' "$route" "$rc" "${http:-000}" >> "$WARP_TRACE"
    printf '%s\n' "$out" | sed '$d'
}

# Picks a WARP endpoint: probes random addresses of the ranges in parallel and prints
# "<address>:<port>" of the fastest that answers from a data centre other than DME.
# Fails when none answers.
warp_pick_endpoint() {
    local dir ip count=0 best

    dir="$(mktemp -d "${TMPDIR:-/tmp}/netshift-warp-ep.XXXXXX")" || return 1
    for ip in $(awk -v prefixes="$WARP_ENDPOINT_PREFIXES" -v n="$WARP_PROBE_COUNT" \
        'BEGIN { srand(); m = split(prefixes, a, " "); for (i = 0; i < n; i++) print a[int(rand() * m) + 1] int(rand() * 256) }'); do
        (
            out="$(curl -s --connect-timeout 2 -m 4 -H 'Host: trace.cloudflare.com' -w '\n%{time_total}' "http://$ip/cdn-cgi/trace" 2> /dev/null)" || exit 0
            colo="$(printf '%s\n' "$out" | sed -n 's/^colo=//p' | sed -n '1p')"
            case "$colo" in
            '' | DME) exit 0 ;;
            esac
            ms="$(printf '%s\n' "$out" | sed -n '$p' | awk '{printf "%d", $1 * 1000}')"
            [ -n "$ms" ] && printf '%s %s\n' "$ms" "$ip" >> "$dir/pings"
        ) &
        count=$((count + 1))
        [ $((count % 20)) -ne 0 ] || wait
    done
    wait

    best="$(sort -n "$dir/pings" 2> /dev/null | sed -n '1p')"
    rm -rf "$dir"
    [ -n "$best" ] || return 1
    printf '%s:%s\n' "${best#* }" "$WARP_ENDPOINT_PORT"
}

# The addresses of the API found over HTTPS, one per line (empty when no resolver
# answers).
warp_resolve_api() {
    local url address

    for url in $WARP_DOH_URLS; do
        curl -s -m "$WARP_API_TIMEOUT" --connect-timeout "$WARP_CONNECT_TIMEOUT" -H 'accept: application/dns-json' \
            "$url?name=$WARP_API_HOST&type=A" 2> /dev/null |
            jq -r '.Answer[]? | select(.type == 1) | .data' 2> /dev/null |
            while IFS= read -r address; do
                is_ipv4 "$address" && printf '%s\n' "$address"
            done
    done | sed -n '1,2p'
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

# Reads a field of an API answer, with or without the {"result": ...} wrapper some
# versions of the API (and the relays of them) use. $1 JSON, $2 jq expression.
warp_field() {
    printf '%s' "$1" | jq -r "(.result // .) | ($2) // empty" 2> /dev/null
}

# Registers a device. Prints, one per line: private key, peer public key, IPv4
# address, IPv6 address. The ways to reach the API are tried in turn: through the
# relay (when given), the router's own way, the API address found over HTTPS and
# the ones it has been served from, the NetShift service proxy. $1 - relay URL
# (optional).
warp_register() {
    local relay="$1"
    local keys private public body reg id token cfg peer v4 v6 route routes address answered

    keys="$(warp_keypair)" || return 1
    private="$(printf '%s\n' "$keys" | sed -n '1p')"
    public="$(printf '%s\n' "$keys" | sed -n '2p')"

    body="{\"install_id\":\"\",\"tos\":\"$(date -u +%FT%TZ)\",\"key\":\"$public\",\"fcm_token\":\"\",\"type\":\"ios\",\"locale\":\"en_US\"}"

    routes=""
    [ -z "$relay" ] || routes="relay:$relay"
    routes="$routes plain"
    for address in $(warp_resolve_api) $WARP_API_FALLBACK_IPS; do
        case " $routes " in
        *" ip:$address "*) ;;
        *) routes="$routes ip:$address" ;;
        esac
    done
    if command -v get_service_proxy_address > /dev/null 2>&1; then
        address="$(get_service_proxy_address 2> /dev/null)"
        [ -z "$address" ] || routes="$routes proxy:$address"
    fi

    peer=""
    v4=""
    v6=""
    answered=""
    for route in $routes; do
        reg="$(warp_api_call POST reg "" "$body" "$route")"
        cfg="$reg"
        id="$(warp_field "$reg" '.id')"
        token="$(warp_field "$reg" '.token')"
        [ -z "$id$token" ] || answered="yes"

        # the answer to the registration may carry the configuration already (and a relay
        # may not pass the token); otherwise ask for it
        peer="$(warp_field "$cfg" '.config.peers[0].public_key')"
        v4="$(warp_field "$cfg" '.config.interface.addresses.v4')"
        if [ -n "$id" ] && [ -n "$token" ]; then
            cfg="$(warp_api_call PATCH "reg/$id" "$token" '{"warp_enabled":true}' "$route")"
            if [ -n "$(warp_field "$cfg" '.config.peers[0].public_key')" ]; then
                peer="$(warp_field "$cfg" '.config.peers[0].public_key')"
                v4="$(warp_field "$cfg" '.config.interface.addresses.v4')"
            else
                cfg="$reg"
            fi
        fi
        [ -z "$peer" ] || [ -z "$v4" ] || break
        peer=""
        v4=""
    done
    if [ -z "$peer" ] || [ -z "$v4" ]; then
        # an answer was there but without a configuration: another error than silence
        [ -z "$answered" ] || return 3
        return 2
    fi
    v6="$(warp_field "$cfg" '.config.interface.addresses.v6')"

    printf '%s\n%s\n%s\n%s\n' "$private" "$peer" "$v4" "$v6"
}

# Writes an interface and its peer into /etc/config/network (replacing both).
# $1 name, $2 proto, $3 private key, $4 addresses (CIDR, blank separated), $5 MTU,
# $6 peer key, $7 pre-shared key (or empty), $8 endpoint host, $9 endpoint port,
# $10 allowed IPs (blank separated), $11 keepalive, $12 AmneziaWG options, one
# "<name> <value>" per line (the part after the first blank is the value).
warp_write_profile() {
    local name="$1"
    local proto="$2"
    local private="$3"
    local addresses="$4"
    local mtu="$5"
    local peer_key="$6"
    local psk="$7"
    local host="$8"
    local port="$9"
    local allowed="${10}"
    local keepalive="${11}"
    local awg="${12}"
    local peer_section="${proto}_${name}"
    local address line key

    uci -q delete "network.$name"
    uci -q delete "network.amneziawg_$name"
    uci -q delete "network.wireguard_$name"

    uci set "network.$name=interface"
    uci set "network.$name.proto=$proto"
    uci set "network.$name.private_key=$private"
    for address in $addresses; do
        uci add_list "network.$name.addresses=$address"
    done
    [ -z "$mtu" ] || uci set "network.$name.mtu=$mtu"

    if [ "$proto" = "amneziawg" ]; then
        printf '%s\n' "$awg" | while IFS= read -r line; do
            [ -n "$line" ] || continue
            key="${line%% *}"
            uci set "network.$name.awg_$key=${line#* }"
        done
    fi

    uci set "network.$peer_section=$peer_section"
    uci set "network.$peer_section.interface=$name"
    uci set "network.$peer_section.public_key=$peer_key"
    [ -z "$psk" ] || uci set "network.$peer_section.preshared_key=$psk"
    uci set "network.$peer_section.endpoint_host=$host"
    uci set "network.$peer_section.endpoint_port=$port"
    for address in $allowed; do
        uci add_list "network.$peer_section.allowed_ips=$address"
    done
    # NetShift binds its own outbound to the interface; a default route through
    # the tunnel would send the whole router there
    uci set "network.$peer_section.route_allowed_ips=0"
    [ -z "$keepalive" ] || uci set "network.$peer_section.persistent_keepalive=$keepalive"
    uci commit network
}

# The WARP interface: $1 name, $2 proto, $3 private key, $4 peer key, $5 IPv4,
# $6 IPv6, $7 endpoint host, $8 port.
warp_write_interface() {
    local awg=""

    if [ "$2" = "amneziawg" ]; then
        awg="jc 4
jmin 40
jmax 70
s1 0
s2 0
h1 1
h2 2
h3 3
h4 4"
        # the signature packet only where the protocol handler knows the option
        if grep -q awg_i1 /lib/netifd/proto/amneziawg.sh 2> /dev/null; then
            awg="$awg
i1 $WARP_AWG_I1"
        fi
    fi

    warp_write_profile "$1" "$2" "$3" "$5/32${6:+ $6/128}" 1280 "$4" "" "$7" "$8" "0.0.0.0/0 ::/0" 25 "$awg"
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

# $1 error, $2 hint (optional), $3 trace file with the attempts (optional)
warp_error() {
    local attempts="[]"

    if [ -n "$3" ] && [ -s "$3" ]; then
        attempts="$(jq -R -s -c 'split("\n") | map(select(length > 0) | split(" ") | {route: .[0], curl: (.[1] | tonumber), http: .[2]})' "$3" 2> /dev/null)" || attempts="[]"
    fi
    jq -n -c --arg error "$1" --arg hint "$2" --argjson attempts "$attempts" \
        '{ok: false, error: $error, hint: (if $hint == "" then null else $hint end), attempts: $attempts}'
}

# warp_generate [endpoint|auto] [interface] [proto] [relay-url]
# Registers a WARP device and sets up the interface and the section. Prints
# {"ok":true,...} or {"ok":false,"error":...}.
warp_generate() {
    local endpoint="${1:-}"
    local name="${2:-}"
    local proto="${3:-}"
    local relay="${4:-}"
    local profile private peer v4 v6 rc host port trace hint

    [ -n "$endpoint" ] || endpoint="${WARP_ENDPOINTS%% *}"
    [ -n "$name" ] || name="$WARP_INTERFACE_DEFAULT"

    # "auto": the fastest address of the ranges, else the usual name
    if [ "$endpoint" = "auto" ]; then
        endpoint="$(warp_pick_endpoint)" || endpoint="${WARP_ENDPOINTS%% *}"
    fi

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

    case "$relay" in
    "" | https://* | http://*) ;;
    *)
        warp_error "the relay must be an http(s) URL" ""
        return 1
        ;;
    esac

    trace="$(mktemp "${TMPDIR:-/tmp}/netshift-warp.XXXXXX")" || trace=""
    WARP_TRACE="$trace"
    profile="$(warp_register "$relay")"
    rc=$?
    WARP_TRACE=""
    case "$rc" in
    0) ;;
    1)
        warp_error "could not make a key pair" "the sing-box core or wireguard-tools is needed" "$trace"
        rm -f "$trace"
        return 1
        ;;
    2)
        hint="api.cloudflareclient.com seems to be blocked here: use a relay (your own reverse proxy of the API) or try another network"
        if ! command -v get_service_proxy_address > /dev/null 2>&1 || [ -z "$(get_service_proxy_address 2> /dev/null)" ]; then
            hint="$hint; or turn on 'Download lists via Proxy/VPN' in the settings, then the router also tries the API through that section"
        fi
        warp_error "Cloudflare did not answer the registration" "$hint" "$trace"
        rm -f "$trace"
        return 1
        ;;
    *)
        warp_error "Cloudflare did not return the configuration" "" "$trace"
        rm -f "$trace"
        return 1
        ;;
    esac
    rm -f "$trace"

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

# ── Import of a ready WireGuard / AmneziaWG config ──────────────────────────────
# For the places where the registration cannot be made from the router at all: the
# config is made elsewhere (a cloud shell, a generator site) and pasted here.

# Reads a config on stdin and prints "<section>.<key><TAB><value>" lines, the section
# and the key in lower case ("interface.privatekey", "peer.endpoint", ...).
warp_conf_lines() {
    awk '
        function trim(s) { gsub(/^[ \t\r]+|[ \t\r]+$/, "", s); return s }
        {
            line = trim($0)
            if (line == "" || line ~ /^[#;]/) next
            if (line ~ /^\[.*\]$/) {
                section = tolower(substr(line, 2, length(line) - 2))
                # only the first peer is used: the others get their own names
                if (section == "peer" && ++peers > 1) section = "peer" peers
                next
            }
            i = index(line, "=")
            if (!i) next
            print section "." tolower(trim(substr(line, 1, i - 1))) "\t" trim(substr(line, i + 1))
        }'
}

warp_valid_key() {
    printf '%s' "$1" | grep -Eq '^[A-Za-z0-9+/]{43}=$'
}

# "172.16.0.2" -> "172.16.0.2/32", "2606::1" -> "2606::1/128"; fails for anything else
warp_cidr() {
    local address="${1%%/*}"
    local mask=""

    case "$1" in
    */*) mask="${1#*/}" ;;
    esac
    case "$mask" in
    *[!0-9]*) return 1 ;;
    esac

    if is_ipv4 "$address"; then
        printf '%s/%s\n' "$address" "${mask:-32}"
    elif is_ipv6 "$address"; then
        printf '%s/%s\n' "$address" "${mask:-128}"
    else
        return 1
    fi
}

# warp_import <config text> [interface]
# Makes the interface and the VPN section from a pasted config. Prints
# {"ok":true,...} or {"ok":false,"error":...}.
warp_import() {
    local text="$1"
    local name="${2:-}"
    local lines key value private mtu peer_key psk endpoint host port keepalive
    local addresses="" allowed="" awg="" skipped="" proto cidr item option wanted_awg=""

    [ -n "$name" ] || name="$WARP_INTERFACE_DEFAULT"
    warp_valid_interface_name "$name" || {
        warp_error "invalid interface name" ""
        return 1
    }
    if [ -n "$(uci -q get "network.$name")" ]; then
        warp_error "the interface '$name' already exists" "remove it or choose another name"
        return 1
    fi

    lines="$(printf '%s\n' "$text" | warp_conf_lines)"
    private=""
    mtu=""
    peer_key=""
    psk=""
    endpoint=""
    keepalive=""

    while IFS="$(printf '\t')" read -r key value; do
        [ -n "$key" ] || continue
        case "$key" in
        peer.publickey) peer_key="$value" ;;
        interface.privatekey) private="$value" ;;
        interface.address)
            for item in $(printf '%s' "$value" | tr ',' ' '); do
                cidr="$(warp_cidr "$item")" || {
                    warp_error "invalid address '$item'" ""
                    return 1
                }
                addresses="$addresses $cidr"
            done
            ;;
        interface.mtu) mtu="$value" ;;
        interface.jc | interface.jmin | interface.jmax | interface.s1 | interface.s2 | interface.s3 | interface.s4 | \
            interface.h1 | interface.h2 | interface.h3 | interface.h4 | interface.i1 | interface.i2 | interface.i3 | interface.i4 | interface.i5)
            option="${key#interface.}"
            wanted_awg="$wanted_awg
$option $value"
            ;;
        peer.presharedkey) psk="$value" ;;
        peer.endpoint) endpoint="$value" ;;
        peer.persistentkeepalive) keepalive="$value" ;;
        peer.allowedips)
            for item in $(printf '%s' "$value" | tr ',' ' '); do
                cidr="$(warp_cidr "$item")" || {
                    warp_error "invalid allowed address '$item'" ""
                    return 1
                }
                allowed="$allowed $cidr"
            done
            ;;
        esac
    done << EOF
$lines
EOF

    warp_valid_key "$private" || {
        warp_error "the config has no valid PrivateKey" ""
        return 1
    }
    warp_valid_key "$peer_key" || {
        warp_error "the config has no valid peer PublicKey" ""
        return 1
    }
    [ -z "$psk" ] || warp_valid_key "$psk" || {
        warp_error "invalid PresharedKey" ""
        return 1
    }
    [ -n "$addresses" ] || {
        warp_error "the config has no Address" ""
        return 1
    }

    # endpoint: host:port, [v6]:port
    case "$endpoint" in
    \[*\]:*)
        host="${endpoint%\]:*}"
        host="${host#\[}"
        port="${endpoint##*:}"
        ;;
    *:*)
        host="${endpoint%:*}"
        port="${endpoint##*:}"
        ;;
    *)
        warp_error "the config has no valid Endpoint (host:port)" ""
        return 1
        ;;
    esac
    case "$port" in
    '' | *[!0-9]*)
        warp_error "invalid Endpoint port" ""
        return 1
        ;;
    esac
    { [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; } || {
        warp_error "invalid Endpoint port" ""
        return 1
    }
    is_domain "$host" || is_ipv4 "$host" || is_ipv6 "$host" || {
        warp_error "invalid Endpoint host" ""
        return 1
    }
    case "$mtu" in
    '' | *[!0-9]*) [ -z "$mtu" ] || {
        warp_error "invalid MTU" ""
        return 1
    } ;;
    esac
    case "$keepalive" in
    *[!0-9]*)
        warp_error "invalid PersistentKeepalive" ""
        return 1
        ;;
    esac
    [ -n "$allowed" ] || allowed="0.0.0.0/0 ::/0"

    # the protocol: AmneziaWG options need the AmneziaWG handler
    if [ -n "$wanted_awg" ]; then
        if [ -f /lib/netifd/proto/amneziawg.sh ]; then
            proto="amneziawg"
        else
            warp_error "the config has AmneziaWG options but the amneziawg protocol is not installed" "install amneziawg-tools with luci-proto-amneziawg"
            return 1
        fi
    else
        proto="$(warp_detect_proto_plain)"
        [ -n "$proto" ] || {
            warp_error "no WireGuard support for the network interfaces" "install the wireguard-tools package"
            return 1
        }
    fi

    # options the protocol handler does not know are left out and reported
    if [ "$proto" = "amneziawg" ]; then
        while IFS= read -r item; do
            [ -n "$item" ] || continue
            option="${item%% *}"
            case "$option" in
            s3 | s4 | i1 | i2 | i3 | i4 | i5)
                if grep -q "awg_$option" /lib/netifd/proto/amneziawg.sh 2> /dev/null; then
                    awg="$awg
$item"
                else
                    skipped="$skipped $option"
                fi
                ;;
            *) awg="$awg
$item" ;;
            esac
        done << EOF
$wanted_awg
EOF
    fi

    warp_write_profile "$name" "$proto" "$private" "${addresses# }" "$mtu" "$peer_key" "$psk" "$host" "$port" "${allowed# }" "${keepalive:-25}" "$awg"
    warp_write_section "$name"
    warp_reload_services "$name"

    case "$host" in
    *:*) host="[$host]" ;;
    esac
    jq -n -c --arg interface "$name" --arg proto "$proto" --arg endpoint "$host:$port" --arg skipped "${skipped# }" \
        '{ok: true, interface: $interface, section: $interface, proto: $proto, endpoint: $endpoint,
          skipped: ($skipped | split(" ") | map(select(length > 0)))}'
}

# The protocol for a config without AmneziaWG options: plain WireGuard, else AmneziaWG
# (it carries a plain config too).
warp_detect_proto_plain() {
    if [ -f /lib/netifd/proto/wireguard.sh ]; then
        echo "wireguard"
    elif [ -f /lib/netifd/proto/amneziawg.sh ]; then
        echo "amneziawg"
    fi
}
