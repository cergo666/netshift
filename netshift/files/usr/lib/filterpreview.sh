# shellcheck shell=ash
#
# A preview of the subscription filters of a section: how many servers of the downloaded
# subscription stay with the filters as they are in the form (not yet saved). It works on the
# cached feeds of the last start, downloads nothing and changes nothing.

# $1 = section, $2 = {"<option>": ["value", ...]} for the options the form holds right now
# (any option of the section: the filter lists). Prints
# {"total": N, "kept": M, "names": [..kept names..], "dropped": [..first names dropped..]}
# or {"error": "no_cache"|"no_section"|"bad_input"}.
preview_subscription_filter() {
    local section="$1"
    local overrides="${2:-}"
    local tmp_dir keys key value
    local include_json exclude_json urls_file merged_file batch total

    [ -n "$overrides" ] || overrides="{}"
    if [ -z "$section" ] || ! printf '%s' "$overrides" | jq -e 'type == "object"' > /dev/null 2>&1; then
        echo '{"error":"bad_input"}'
        return 0
    fi

    tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/netshift-preview.XXXXXX")" || {
        echo '{"error":"bad_input"}'
        return 0
    }
    cp "$NETSHIFT_CONFIG" "$tmp_dir/netshift" 2> /dev/null || {
        rm -rf "$tmp_dir"
        echo '{"error":"no_section"}'
        return 0
    }

    # Only the filter lists may be overridden
    keys="$(printf '%s' "$overrides" | jq -r 'keys[] | select(startswith("subscription_filter_"))' 2> /dev/null)"
    for key in $keys; do
        case "$key" in
        *[!a-z_]*) continue ;;
        esac
        uci -q -c "$tmp_dir" delete "netshift.$section.$key" 2> /dev/null
        printf '%s' "$overrides" | jq -r --arg k "$key" '.[$k][]? | tostring' 2> /dev/null |
            while IFS= read -r value; do
                [ -n "$value" ] && uci -q -c "$tmp_dir" add_list "netshift.$section.$key=$value"
            done
    done

    # without a commit the changes stay in uci's save directory and would reach the next call
    uci -q -c "$tmp_dir" commit netshift 2> /dev/null

    urls_file="$tmp_dir/urls"
    merged_file="$tmp_dir/merged.json"
    printf '%s' '{"outbounds":[]}' > "$merged_file"

    batch="$(
        # a subshell: the configuration loaded here is the preview copy
        UCI_CONFIG_DIR="$tmp_dir" config_load netshift
        include_json="$(build_subscription_filter_json "$section" "subscription_filter_include_keywords" "subscription_filter_include_countries")"
        exclude_json="$(build_subscription_filter_json "$section" "subscription_filter_exclude_keywords" "subscription_filter_exclude_countries")"
        SUBSCRIPTION_PARAM_FILTER="$(build_subscription_param_filter_json "$section")"
        get_subscription_urls_for_section "$section" > "$urls_file"
        subscription_merge_section_feeds "$section" "$urls_file" "$merged_file"
        [ "$SUBSCRIPTION_USABLE_FEED_COUNT" -gt 0 ] || exit 3
        total="$(jq -r '.outbounds | length' "$merged_file" 2> /dev/null)"
        batch="$(sing_box_cf_prepare_subscription_batch '{"outbounds":[]}' "$merged_file" "$include_json" "$exclude_json")" || exit 4
        printf '%s' "$batch" | jq -c --argjson total "${total:-0}" \
            '{total: $total, kept: (.names | length), names: .names}'
    )"
    local rc=$?
    rm -rf "$tmp_dir"

    if [ "$rc" -ne 0 ] || [ -z "$batch" ]; then
        echo '{"error":"no_cache"}'
        return 0
    fi
    printf '%s\n' "$batch"
}
