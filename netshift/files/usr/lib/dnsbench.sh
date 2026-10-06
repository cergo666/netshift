# shellcheck shell=ash
#
# DNS server benchmark: how fast each upstream answers from THIS router (the answer
# depends on the provider and the route, not on a table of "best" servers). Every
# server is asked one question with dig, all at the same time, so the whole run takes
# about as long as the slowest one (DNS_BENCH_TIMEOUT seconds at most). The result is
# a list of milliseconds, null for a server that did not answer or cannot be tested
# with dig (doh3, doq). Nothing is changed.

DNS_BENCH_TIMEOUT=3
DNS_BENCH_DOMAIN="google.com"
DNS_BENCH_MAX_SERVERS=12

# "doh://dns.google/dns-query" -> prints the dig arguments "@<address> <flags>" or
# fails for a server dig cannot ask. The address is the one found through the
# bootstrap resolver ($2), so the lookup of the server's own name does not depend
# on the resolver that is being measured. $1 - server URL, $2 - bootstrap address.
dns_bench_dig_args() {
    local entry="$1"
    local bootstrap="$2"
    local scheme rest host path address

    scheme="${entry%%://*}"
    case "$scheme" in
    udp | tcp | dot | doh) ;;
    *) return 1 ;;
    esac
    rest="${entry#*://}"
    path="/${rest#*/}"
    [ "$path" = "/$rest" ] && path=""
    rest="${rest%%/*}"
    host="$(url_get_host "$rest")"
    [ -n "$host" ] || return 1

    if is_ipv4 "$host" || is_ipv6 "$host"; then
        address="$host"
    else
        address="$(dig @"$bootstrap" "$host" +short +time=2 +tries=1 2> /dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sed -n '1p')"
        [ -n "$address" ] || return 1
    fi

    case "$scheme" in
    udp) echo "@$address" ;;
    tcp) echo "@$address +tcp" ;;
    dot) echo "@$address +tls +tls-hostname=$host" ;;
    doh) echo "@$address +https=${path:-/dns-query} +tls-hostname=$host" ;;
    esac
}

# Milliseconds one server needs to answer, or nothing. $1 - server URL, $2 - bootstrap.
dns_bench_one() {
    local args output ms

    args="$(dns_bench_dig_args "$1" "$2")" || return 1
    # shellcheck disable=SC2086
    output="$(dig $args "$DNS_BENCH_DOMAIN" A +time="$DNS_BENCH_TIMEOUT" +tries=1 2> /dev/null)" || return 1
    printf '%s' "$output" | grep -q 'status: NOERROR' || return 1
    ms="$(printf '%s' "$output" | sed -n 's/^;; Query time: \([0-9]*\) msec.*/\1/p' | sed -n '1p')"
    [ -n "$ms" ] || return 1
    echo "$ms"
}

# dns_benchmark <server>...: with no arguments, the servers of the settings (the main
# one and the pool). Prints {"results":[{"server","ms"}]} in the order asked.
dns_benchmark() {
    local bootstrap dir server index=0 result="[]" ms pid dns_type dns_server

    config_get bootstrap "settings" "bootstrap_dns_server" "77.88.8.8"

    if [ "$#" -eq 0 ]; then
        config_get dns_type "settings" "dns_type" "udp"
        config_get dns_server "settings" "dns_server" "8.8.8.8"
        set -- "$dns_type://$dns_server"
        DNS_BENCH_POOL=""
        config_list_foreach "settings" "dns_pool_server" _dns_bench_collect_pool
        # shellcheck disable=SC2086
        set -- "$@" $DNS_BENCH_POOL
    fi

    dir="$(mktemp -d)" || return 1
    for server in "$@"; do
        index=$((index + 1))
        [ "$index" -le "$DNS_BENCH_MAX_SERVERS" ] || break
        # a stranger's string must not reach the command line as anything but one URL
        case "$server" in
        udp://* | tcp://* | dot://* | doh://* | doh3://* | doq://*) ;;
        *) continue ;;
        esac
        case "$server" in
        *[!A-Za-z0-9:/._@-]*) continue ;;
        esac
        (
            ms="$(dns_bench_one "$server" "$bootstrap")" || ms=""
            printf '%s\n' "$ms" > "$dir/$index.ms"
        ) &
        printf '%s\n' "$server" > "$dir/$index.server"
    done
    wait

    index=0
    for server in "$@"; do
        index=$((index + 1))
        [ -f "$dir/$index.server" ] || continue
        ms="$(cat "$dir/$index.ms" 2> /dev/null)"
        case "$ms" in
        '' | *[!0-9]*) ms="" ;;
        esac
        result="$(printf '%s' "$result" | jq -c --arg server "$server" --arg ms "$ms" \
            '. + [{server: $server, ms: (if $ms == "" then null else ($ms | tonumber) end)}]')"
    done
    rm -rf "$dir"

    jq -n -c --argjson results "$result" '{results: $results}'
}

_dns_bench_collect_pool() {
    DNS_BENCH_POOL="$DNS_BENCH_POOL $1"
}
