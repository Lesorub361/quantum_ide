#!/data/user/0/com.agyru.t2/files/usr/bin/bash
# resolver.sh -- strict dependency closure and install-order resolution.
# Requires index_lookup, index_provider, db_exists and deb_vercmp.

# ver_satisfies VER OP WANT
ver_satisfies() {
    local c; c="$(deb_vercmp "$1" "$3")"
    case "$2" in
        ">=")     [ "$c" != "-1" ] ;;
        "<=")     [ "$c" != "1" ] ;;
        "="|"==") [ "$c" = "0" ] ;;
        ">>"|">") [ "$c" = "1" ] ;;
        "<<"|"<") [ "$c" = "-1" ] ;;
        *)        return 0 ;;
    esac
}

valid_package_name() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9+._-]*$ ]]
}

# choose_dep TERM -> package line (no repository prefix) or empty
choose_dep() {
    local term="$1" out="" alt nm con op ver line installed tab=$'\t'
    # Prefer an already installed alternative only when its actual version
    # satisfies the dependency. Avoid installing nodejs over nodejs-lts.
    while IFS= read -r alt; do
        nm="$(printf '%s' "$alt" | sed 's/^ *//; s/(.*//; s/\[.*//; s/:.*//; s/[[:space:]]*$//')"
        valid_package_name "$nm" || continue
        db_exists "$nm" || continue
        con="$(printf '%s' "$alt" | sed -n 's/.*(\([^)]*\)).*/\1/p')"
        op="$(printf '%s' "$con" | awk '{print $1}')"
        ver="$(printf '%s' "$con" | awk '{print $2}')"
        installed="$(db_get "$nm" version)"
        if [ -n "$ver" ]; then
            [ -n "$installed" ] && ver_satisfies "$installed" "$op" "$ver" || continue
        fi
        printf '%s\t%s\n' "$nm" "$installed"
        return 0
    done <<EOF
$(printf '%s' "$term" | tr '|' '\n')
EOF
    while IFS= read -r alt; do
        alt="$(printf '%s' "$alt" | sed 's/^ *//; s/ *$//')"
        [ -n "$alt" ] || continue
        nm="$(printf '%s' "$alt" | sed 's/(.*//; s/\[.*//; s/:.*//; s/[[:space:]]*$//')"
        con="$(printf '%s' "$alt" | sed -n 's/.*(\([^)]*\)).*/\1/p')"
        op="$(printf '%s' "$con" | awk '{print $1}')"
        ver="$(printf '%s' "$con" | awk '{print $2}')"
        [ -n "$nm" ] || continue
        line="$(index_lookup "$nm")"; line="${line#*"$tab"}"
        if [ -z "$line" ]; then
            line="$(index_provider "$nm")"; line="${line#*"$tab"}"
        fi
        [ -n "$line" ] || continue
        if [ -n "$ver" ]; then
            ver_satisfies "$(printf '%s' "$line" | cut -f2)" "$op" "$ver" || continue
        fi
        out="$line"; break
    done <<EOF
$(printf '%s' "$term" | tr '|' '\n')
EOF
    [ -n "$out" ] && printf '%s\n' "$out"
}

# resolve NAME... -> complete install order, dependencies first. Fails closed
# for invalid names, unresolved dependencies, and cycles; no partial order leaks.
resolve() {
    local work="$PKG_ROOT/tmp/resolve.$$" name entry line provider rootname failed=0 tab=$'\t'
    rm -rf "$work"; mkdir -p "$work"
    for name in "$@"; do
        if ! valid_package_name "$name"; then
            warn "invalid package name: $name"
            failed=1; break
        fi
        db_exists "$name" && continue
        entry="$(index_lookup "$name")"
        if [ -z "$entry" ]; then
            provider="$(index_provider "$name")"
            if [ -z "$provider" ]; then
                warn "unknown package or provider: $name"
                failed=1; break
            fi
            line="${provider#*"$tab"}"; rootname="$(printf '%s' "$line" | cut -f1)"
        else
            line="${entry#*"$tab"}"; rootname="$(printf '%s' "$line" | cut -f1)"
        fi
        if ! r_visit "$rootname" "$work"; then
            failed=1; break
        fi
    done
    if [ "$failed" -eq 0 ] && [ -f "$work/order" ]; then
        cat "$work/order"
    fi
    rm -rf "$work"
    [ "$failed" -eq 0 ]
}

r_visit() {
    local name="$1" work="$2" line deps term cand cname tab=$'\t'
    valid_package_name "$name" || { warn "invalid package name in index: $name"; return 1; }
    [ -f "$work/done/$name" ] && return 0
    db_exists "$name" && return 0
    [ -f "$work/doing/$name" ] && { warn "dependency cycle at: $name"; return 1; }
    line="$(index_lookup "$name")"; line="${line#*"$tab"}"
    [ -n "$line" ] || { warn "unknown package in dependency closure: $name"; return 1; }
    mkdir -p "$work/done" "$work/doing"
    : > "$work/doing/$name"
    deps="$(printf '%s' "$line" | cut -f5) $(printf '%s' "$line" | cut -f6)"
    while IFS= read -r term; do
        term="$(printf '%s' "$term" | sed 's/^ *//; s/ *$//')"
        [ -n "$term" ] || continue
        cand="$(choose_dep "$term")"
        if [ -z "$cand" ]; then
            warn "cannot resolve dependency: $term (for $name)"
            rm -f "$work/doing/$name"
            return 1
        fi
        cname="$(printf '%s' "$cand" | cut -f1)"
        if ! r_visit "$cname" "$work"; then
            rm -f "$work/doing/$name"
            return 1
        fi
    done <<EOF
$(printf '%s' "$deps" | tr ',' '\n')
EOF
    rm -f "$work/doing/$name"
    : > "$work/done/$name"
    printf '%s\n' "$name" >> "$work/order"
}
