# shellcheck shell=ash
#
# Failover to direct: with failover_direct '1' on a proxy section, the traffic of the
# section goes out directly (and is picked up there by whatever handles direct traffic,
# for example zapret) while none of its servers answers, and goes back to the section as
# soon as one does.
#
# sing-box has no fallback outbound, so the section's group (<section>-out, the one the
# dashboard shows) is wrapped in a selector <section>-out-failover with the members
# [<section>-out, direct-out], and everything that pointed to the group (route rules, the
# final route, detours) points to the selector. The monitor probes the servers of the
# group every check cycle (the Clash API probe and the interval of priority selection) and
# moves the selector: FAILOVER_FAILURES failed cycles in a row - to direct-out, the first
# cycle with an answering server - back to the group. A selector that somebody moved by
# hand is left alone.

# Wraps the group of the section. $1 config, $2 group tag, $3 selector tag, $4 direct tag.
# Prints the new config.
failover_wrap_config() {
    printf '%s' "$1" | jq -c --arg t "$2" --arg n "$3" --arg d "$4" '
        (.route.rules // []) as $rules
        | .route.rules |= (map(if (type == "object") and .outbound? == $t then .outbound = $n else . end))
        | (if .route.final? == $t then .route.final = $n else . end)
        | .outbounds |= map(if (type == "object") and .detour? == $t then .detour = $n else . end)
        | (if .dns.servers? then .dns.servers |= map(if .detour? == $t then .detour = $n else . end) else . end)
        | (if .route.rule_set? then .route.rule_set |= map(if .download_detour? == $t then .download_detour = $n else . end) else . end)
        | .outbounds += [{type: "selector", tag: $n, outbounds: [$t, $d], default: $t, interrupt_exist_connections: false}]'
}

# config_foreach callback of the config pass; works on the global $config.
_failover_configure_section_handler() {
    local section="$1"
    local failover connection_type tag selector exists

    config_get_bool failover "$section" "failover_direct" 0
    [ "$failover" -eq 1 ] || return 0
    section_is_disabled "$section" && return 0

    config_get connection_type "$section" "connection_type"
    if [ "$connection_type" != "proxy" ]; then
        log "Failover to direct for section '$section': it applies to proxy sections only; ignoring it" "warn"
        return 0
    fi

    tag="$(get_outbound_tag_by_section "$section")"
    selector="$tag$FAILOVER_TAG_SUFFIX"
    exists="$(printf '%s' "$config" | jq -r --arg t "$tag" '[.outbounds[]? | select(.tag == $t)] | length' 2> /dev/null)"
    if [ "${exists:-0}" -eq 0 ]; then
        log "Failover to direct for section '$section': it has no outbound in the configuration (no servers); ignoring it" "warn"
        return 0
    fi

    config="$(failover_wrap_config "$config" "$tag" "$selector" "$SB_DIRECT_OUTBOUND_TAG")"
    log "Failover to direct for section '$section': '$tag' is wrapped in '$selector'" "debug"
}

# Wraps the groups of all the sections that ask for it (the global $config).
failover_configure() {
    config_foreach _failover_configure_section_handler "section"
}

failover_var_get() {
    local value

    case "$2" in
    "" | *[!A-Za-z0-9_]*)
        echo 0
        return 0
        ;;
    esac
    eval "value=\"\${FAILOVER_$1_$2:-0}\""
    echo "$value"
}

failover_var_set() {
    case "$2" in
    "" | *[!A-Za-z0-9_]*) return 0 ;;
    esac
    eval "FAILOVER_$1_$2=\"$3\""
}

# The servers to probe for the group $1 in the running sing-box, the one in use first:
# one per line. Groups inside the group (country groups) are opened one level. For
# something that is not a group, the tag itself.
failover_probe_candidates() {
    printf '%s' "$FAILOVER_PROXIES_JSON" | jq -r --arg tag "$1" '
        .proxies as $p
        | def isgroup: (($p[.].type // "") as $t | ["Selector", "URLTest", "Fallback", "LoadBalance"] | index($t)) != null;
        def inside: [($p[.].now // "")] + ($p[.].all // []) | map(select(. != ""));
        (if ($tag | isgroup) then
            ($tag | inside)
            | map(if isgroup then (inside | map(select(isgroup | not))) else [.] end)
            | flatten
        else [$tag] end)
        | reduce .[] as $x ([]; if index([$x]) then . else . + [$x] end)
        | .[]' 2> /dev/null
}

# Prints 1 when one of the servers of the group $1 answers, 0 when none does.
failover_group_alive() {
    local member probed=0

    for member in $(failover_probe_candidates "$1" | sed -n "1,${PRIORITY_MAX_PROBES}p" | tr '\n' ' '); do
        [ "$(date +%s)" -lt "$FAILOVER_DEADLINE" ] || break
        probed=$((probed + 1))
        if [ "$(priority_probe_delay "$member")" -gt 0 ]; then
            echo 1
            return 0
        fi
    done
    # nothing to probe (the group is empty or not in the running sing-box): not a failure
    if [ "$probed" -eq 0 ]; then
        echo 1
        return 0
    fi
    echo 0
}

# $1 - section; FAILOVER_PROXIES_JSON holds the proxies of this cycle.
failover_check_section() {
    local section="$1"
    local tag selector now fails active

    tag="$(get_outbound_tag_by_section "$section")"
    selector="$tag$FAILOVER_TAG_SUFFIX"
    now="$(printf '%s' "$FAILOVER_PROXIES_JSON" | jq -r --arg tag "$selector" '.proxies[$tag].now // empty' 2> /dev/null)"
    # not in the running sing-box (the option was set after the last start): nothing to do
    [ -n "$now" ] || return 0

    fails="$(failover_var_get FAILS "$section")"
    active="$(failover_var_get ACTIVE "$section")"

    if [ "$now" = "$tag" ]; then
        # the group is in use: the usual state (a restart of sing-box lands here too)
        active=0
        failover_var_set ACTIVE "$section" 0
        if [ "$(failover_group_alive "$tag")" -eq 1 ]; then
            failover_var_set FAILS "$section" 0
            return 0
        fi
        fails=$((fails + 1))
        if [ "$fails" -lt "$FAILOVER_FAILURES" ]; then
            failover_var_set FAILS "$section" "$fails"
            log "Failover to direct for section '$section': no server answers ($fails/$FAILOVER_FAILURES)" "info"
            return 0
        fi
        failover_var_set FAILS "$section" 0
        if clash_api set_group_proxy "$selector" "$SB_DIRECT_OUTBOUND_TAG" > /dev/null 2>&1; then
            failover_var_set ACTIVE "$section" 1
            log "Failover to direct for section '$section': no server answers, its traffic goes out directly" "warn"
        else
            log "Failover to direct for section '$section': could not switch to direct" "warn"
        fi
        return 0
    fi

    if [ "$active" -eq 1 ] && [ "$now" = "$SB_DIRECT_OUTBOUND_TAG" ]; then
        if [ "$(failover_group_alive "$tag")" -eq 1 ]; then
            if clash_api set_group_proxy "$selector" "$tag" > /dev/null 2>&1; then
                failover_var_set ACTIVE "$section" 0
                log "Failover to direct for section '$section': a server answers again, its traffic goes back to the section" "info"
            else
                log "Failover to direct for section '$section': could not switch back to '$tag'" "warn"
            fi
        fi
        return 0
    fi

    # moved by hand (or by something else): not ours any more
    failover_var_set ACTIVE "$section" 0
    failover_var_set FAILS "$section" 0
}

_failover_collect_section_handler() {
    local section="$1"
    local failover connection_type

    config_get_bool failover "$section" "failover_direct" 0
    [ "$failover" -eq 1 ] || return 0
    section_is_disabled "$section" && return 0
    config_get connection_type "$section" "connection_type"
    [ "$connection_type" = "proxy" ] || return 0

    FAILOVER_SECTIONS_TO_CHECK="$FAILOVER_SECTIONS_TO_CHECK $section"
}

# One cycle, called from the monitor next to the priority check.
failover_check_sections() {
    local section

    FAILOVER_SECTIONS_TO_CHECK=""
    config_foreach _failover_collect_section_handler "section"
    [ -n "$FAILOVER_SECTIONS_TO_CHECK" ] || return 0

    FAILOVER_DEADLINE=$(($(date +%s) + PRIORITY_CYCLE_BUDGET))
    priority_clash_setup
    FAILOVER_PROXIES_JSON="$(priority_fetch_proxies)"
    [ -n "$FAILOVER_PROXIES_JSON" ] || return 0

    for section in $FAILOVER_SECTIONS_TO_CHECK; do
        failover_check_section "$section"
    done
}
