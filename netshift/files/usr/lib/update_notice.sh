# shellcheck shell=ash
#
# "A newer version is available" notice for the dashboard. The answer is kept in a
# small file in tmpfs: the dashboard reads it without any network access
# (get_update_notice) and, when it is older than UPDATE_NOTICE_TTL and the option
# is on, starts one background refresh (update_notice_refresh_async) that asks
# GitHub through the same checks the Component Manager uses. Nothing is installed.

# One JSON object: {"checked": <epoch>, "netshift": {...}, "sing_box": {...}}.
# Each part is the answer of the matching check (success, current_version,
# latest_version, status) or null when the check failed or does not apply.
update_notice_collect() {
    local netshift_json sing_box_json variant now

    now="$(date +%s)"
    netshift_json="$(updates_check_netshift 2> /dev/null | jq -c 'select(.success == true)' 2> /dev/null)"
    [ -n "$netshift_json" ] || netshift_json="null"

    # Only the cores that come from GitHub: the stock core would need a package
    # feed refresh, which is not something to do in the background.
    sing_box_json="null"
    variant="$(get_sing_box_variant)"
    case "$variant" in
    extended)
        sing_box_json="$(updates_check_sing_box_extended 2> /dev/null | jq -c 'select(.success == true)' 2> /dev/null)"
        ;;
    extended_lite)
        sing_box_json="$(updates_check_sing_box_lite 2> /dev/null | jq -c 'select(.success == true)' 2> /dev/null)"
        ;;
    esac
    [ -n "$sing_box_json" ] || sing_box_json="null"

    jq -n -c --argjson checked "$now" --argjson netshift "$netshift_json" --argjson sing_box "$sing_box_json" \
        '{checked: $checked, netshift: $netshift, sing_box: $sing_box}'
}

# Runs the checks and stores the answer. A run that learned nothing (both null,
# i.e. GitHub not reachable) keeps the previous answer.
update_notice_refresh() {
    local result tmp

    result="$(update_notice_collect)"
    if [ "$(printf '%s' "$result" | jq -r '(.netshift == null) and (.sing_box == null)')" = "true" ]; then
        # Remember that we tried, so an unreachable GitHub is not asked again on
        # every page load: only the time moves.
        if [ -s "$UPDATE_NOTICE_FILE" ]; then
            result="$(jq -c --argjson checked "$(date +%s)" '.checked = $checked' "$UPDATE_NOTICE_FILE" 2> /dev/null)"
        fi
        [ -n "$result" ] || result="$(update_notice_collect)"
    fi

    tmp="$UPDATE_NOTICE_FILE.tmp.$$"
    printf '%s\n' "$result" > "$tmp" && mv "$tmp" "$UPDATE_NOTICE_FILE"
}

# Starts a refresh that outlives the caller (the RPC session may close), unless one
# is running already. Prints {"started":true|false}.
update_notice_refresh_async() {
    local lock="$UPDATE_NOTICE_FILE.lock"
    local pid

    pid="$(cat "$lock" 2> /dev/null)"
    if [ -n "$pid" ] && kill -0 "$pid" 2> /dev/null; then
        echo '{"started":false}'
        return 0
    fi

    (
        trap '' HUP
        update_notice_refresh
        rm -f "$lock"
    ) > /dev/null 2>&1 &
    printf '%s' "$!" > "$lock"
    echo '{"started":true}'
}

# What the dashboard shows. {"enabled": bool, "stale": bool, "checked": epoch|null,
# "netshift": {...}|null, "sing_box": {...}|null}. No network access.
get_update_notice() {
    local enabled now data checked

    config_get_bool enabled "settings" "update_notice" 1
    now="$(date +%s)"

    data="$(cat "$UPDATE_NOTICE_FILE" 2> /dev/null)"
    printf '%s' "$data" | jq -e 'type == "object"' > /dev/null 2>&1 || data="{}"

    checked="$(printf '%s' "$data" | jq -r '.checked // 0')"
    case "$checked" in
    '' | *[!0-9]*) checked=0 ;;
    esac

    # The answer is kept for a day, but it names the versions it was made for. After an
    # update (or a switch of the core) it would keep offering "0.9.10.4 -> 0.9.11.1" on a
    # router that already runs 0.9.11.3: a part whose "current_version" is not what is
    # installed now is dropped and the notice is due for a refresh.
    sing_box_now=""
    if [ "$(printf '%s' "$data" | jq -r '.sing_box.current_version // empty')" != "" ]; then
        sing_box_now="$(get_sing_box_version 2> /dev/null)"
    fi

    printf '%s' "$data" | jq -c --argjson enabled "$([ "$enabled" -eq 1 ] && echo true || echo false)" \
        --argjson stale "$([ $((now - checked)) -ge "$UPDATE_NOTICE_TTL" ] && echo true || echo false)" \
        --arg netshift_now "${NETSHIFT_VERSION:-}" --arg sing_box_now "$sing_box_now" '
        def outdated($part; $now):
            ($part != null) and ($now != "") and (($part.current_version // "") != $now);
        outdated(.netshift; $netshift_now) as $ns_old
        | outdated(.sing_box; $sing_box_now) as $sb_old
        | {
            enabled: $enabled,
            stale: ($stale or $ns_old or $sb_old),
            checked: (.checked // null),
            netshift: (if $ns_old then null else (.netshift // null) end),
            sing_box: (if $sb_old then null else (.sing_box // null) end)
        }'
}
