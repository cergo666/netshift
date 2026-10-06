# shellcheck shell=ash
# Constructs and returns a ruleset tag using section, name, optional type, and a fixed postfix
get_ruleset_tag() {
    local section="$1"
    local name="$2"
    local type="$3"
    local postfix="ruleset"

    if [ -n "$type" ]; then
        echo "$section-$name-$type-$postfix"
    else
        echo "$section-$name-$postfix"
    fi
}

# Creates a new ruleset JSON file if it doesn't already exist
create_source_rule_set() {
    local ruleset_filepath="$1"

    if file_exists "$ruleset_filepath"; then
        return 3
    fi

    jq -n '{version: 3, rules: []}' > "$ruleset_filepath"
}

#######################################
# Patch a source ruleset JSON file for sing-box by appending a new ruleset object containing the provided key
# and value.
# Arguments:
#   filepath: path to the JSON file to patch
#   key: the ruleset key to insert (e.g., "ip_cidr")
#   value: a JSON array of values to assign to the key
# Example:
#   patch_source_ruleset_rules "/tmp/sing-box/ruleset.json" "ip_cidr" '["1.1.1.1","2.2.2.2"]'
#######################################
patch_source_ruleset_rules() {
    local filepath="$1"
    local key="$2"
    local value="$3"

    local tmpfile=$(mktemp)

    jq --arg key "$key" --argjson value "$value" \
        '( .rules | map(has($key)) | index(true) ) as $idx |
        if $idx != null then
            .rules[$idx][$key] = (.rules[$idx][$key] + $value | unique)
        else
            .rules += [{ ($key): $value }]
        end' "$filepath" > "$tmpfile"

    if [ $? -ne 0 ]; then
        rm -f "$tmpfile"
        return 1
    fi

    mv "$tmpfile" "$filepath"
}

# Drops the regular expressions that the core would refuse: one broken pattern
# would fail the whole configuration check and the service would not start.
# $1 - file with one pattern per line; prints the valid ones, one per line.
validate_domain_regex_file() {
    local input="$1"
    local probe line

    [ -s "$input" ] || return 0

    probe="$(mktemp)"
    jq -R -s '{version: 3, rules: [{domain_regex: (split("\n") | map(select(length > 0)))}]}' "$input" > "$probe"
    if sing-box rule-set match "$probe" "netshift-probe.invalid" > /dev/null 2>&1; then
        rm -f "$probe"
        cat "$input"
        return 0
    fi

    # Something is wrong: find the culprits one by one.
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        jq -n --arg re "$line" '{version: 3, rules: [{domain_regex: [$re]}]}' > "$probe"
        if sing-box rule-set match "$probe" "netshift-probe.invalid" > /dev/null 2>&1; then
            printf '%s\n' "$line"
        else
            log "Ignoring domain regex '$line': it is not a valid regular expression" "warn" >&2
        fi
    done < "$input"
    rm -f "$probe"
}

# Appends the lines of a file (one JSON-string-safe value per line) to a source
# ruleset as the given key, in one jq call.
patch_source_ruleset_rules_from_file() {
    local ruleset_filepath="$1"
    local key="$2"
    local values_file="$3"
    local json_array

    [ -s "$values_file" ] || return 0
    json_array="$(jq -R -s -c 'split("\n") | map(select(length > 0))' "$values_file")"
    patch_source_ruleset_rules "$ruleset_filepath" "$key" "$json_array"
}

# Imports a plain domain list into a ruleset in chunks, validating entries. A bare
# domain becomes a domain_suffix rule; full:, keyword: and regex: entries (see
# domain_rule_normalize) become domain, domain_keyword and domain_regex rules.
# Domains are lowercased before validation (issue #52), so a mixed-case entry
# such as "Example.COM" becomes "example.com" instead of being dropped.
import_plain_domain_list_to_local_source_ruleset_chunked() {
    local plain_list_filepath="$1"
    local ruleset_filepath="$2"
    local chunk_size="${3:-1000}"

    local array count json_array entry
    local full_file keyword_file regex_file valid_regex_file
    full_file="$(mktemp)"
    keyword_file="$(mktemp)"
    regex_file="$(mktemp)"
    count=0
    while IFS= read -r line; do
        line=$(printf '%s\n' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        [ -z "$line" ] && continue

        if ! entry="$(domain_rule_normalize "$line")"; then
            log "'$line' is not a valid domain" "debug"
            continue
        fi

        case "$entry" in
        full:*)
            printf '%s\n' "${entry#full:}" >> "$full_file"
            continue
            ;;
        keyword:*)
            printf '%s\n' "${entry#keyword:}" >> "$keyword_file"
            continue
            ;;
        regex:*)
            printf '%s\n' "${entry#regex:}" >> "$regex_file"
            continue
            ;;
        esac
        line="$entry"

        if [ -z "$array" ]; then
            array="$line"
        else
            array="$array,$line"
        fi

        count=$((count + 1))

        if [ "$count" = "$chunk_size" ]; then
            log "Adding $count elements to rule set at $ruleset_filepath" "debug"
            json_array="$(comma_string_to_json_array "$array")"
            patch_source_ruleset_rules "$ruleset_filepath" "domain_suffix" "$json_array"
            array=""
            count=0
        fi
    done < "$plain_list_filepath"

    if [ -n "$array" ]; then
        log "Adding $count elements to rule set at $ruleset_filepath" "debug"
        json_array="$(comma_string_to_json_array "$array")"
        patch_source_ruleset_rules "$ruleset_filepath" "domain_suffix" "$json_array"
    fi

    patch_source_ruleset_rules_from_file "$ruleset_filepath" "domain" "$full_file"
    patch_source_ruleset_rules_from_file "$ruleset_filepath" "domain_keyword" "$keyword_file"
    valid_regex_file="$(mktemp)"
    validate_domain_regex_file "$regex_file" > "$valid_regex_file"
    patch_source_ruleset_rules_from_file "$ruleset_filepath" "domain_regex" "$valid_regex_file"
    rm -f "$full_file" "$keyword_file" "$regex_file" "$valid_regex_file"
}

# Imports a plain IPv4/CIDR list into a ruleset in chunks, validating entries and appending them as ip_cidr rules
import_plain_subnet_list_to_local_source_ruleset_chunked() {
    local plain_list_filepath="$1"
    local ruleset_filepath="$2"
    local chunk_size="${3:-1000}"

    local array count json_array
    count=0
    while IFS= read -r line; do
        line=$(printf '%s\n' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        [ -z "$line" ] && continue

        if ! is_ipv4 "$line" && ! is_ipv4_cidr "$line"; then
            log "'$line' is not IPv4 or IPv4 CIDR" "debug"
            continue
        fi

        if [ -z "$array" ]; then
            array="$line"
        else
            array="$array,$line"
        fi

        count=$((count + 1))

        if [ "$count" = "$chunk_size" ]; then
            log "Adding $count elements to ruleset at $ruleset_filepath" "debug"
            json_array="$(comma_string_to_json_array "$array")"
            patch_source_ruleset_rules "$ruleset_filepath" "ip_cidr" "$json_array"
            array=""
            count=0
        fi
    done < "$plain_list_filepath"

    if [ -n "$array" ]; then
        log "Adding $count elements to ruleset at $ruleset_filepath" "debug"
        json_array="$(comma_string_to_json_array "$array")"
        patch_source_ruleset_rules "$ruleset_filepath" "ip_cidr" "$json_array"
    fi
}

# Determines the ruleset format based on the file extension (json → source, srs → binary)
get_ruleset_format_by_file_extension() {
    local file_extension="$1"

    local format
    case "$file_extension" in
    json) format="source" ;;
    srs) format="binary" ;;
    *)
        log "Unsupported file extension: .$file_extension" "error"
        return 1
        ;;
    esac

    echo "$format"
}

# Decompiles a sing-box SRS binary file into a JSON ruleset file
decompile_binary_ruleset() {
    local binary_filepath="$1"
    local output_filepath="$2"

    log "Decompiling $binary_filepath to $output_filepath" "debug"
    if ! sing-box rule-set decompile "$binary_filepath" -o "$output_filepath"; then
        log "Decompilation command failed for $binary_filepath" "error"
        return 1
    fi
}

# Extracts all ip_cidr entries from a JSON ruleset file and writes them to an output file.
extract_ip_cidr_from_json_ruleset_to_file() {
    local json_file="$1"
    local output_file="$2"

    log "Extracting ip_cidr entries from $json_file to $output_file" "debug"
    jq -r '.rules[].ip_cidr[]' "$json_file" > "$output_file"
}
