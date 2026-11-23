#!/data/user/0/com.agyru.t2/files/usr/bin/bash
# db.sh -- installed-package database. One .meta + one .files per package.

db_meta()  { printf '%s/%s.meta'  "$PKG_DB" "$1"; }
db_files() { printf '%s/%s.files' "$PKG_DB" "$1"; }

db_exists() { [ -f "$(db_meta "$1")" ]; }

db_get() {
    local f; f="$(db_meta "$1")"
    [ -f "$f" ] || return 1
    sed -n "s/^$2=//p" "$f" | head -n 1
}

# db_put NAME VERSION ARCH < files-list
db_put() {
    ensure_dirs
    local name="$1" ver="$2" arch="$3" m f
    m="$(db_meta "$name")"; f="$(db_files "$name")"
    { printf 'name=%s\n' "$name"; printf 'version=%s\n' "$ver"; printf 'arch=%s\n' "$arch"; } > "$m.tmp"
    cat > "$f.tmp"
    mv "$m.tmp" "$m"; mv "$f.tmp" "$f"
}

db_remove() { rm -f "$(db_meta "$1")" "$(db_files "$1")"; }

db_list() {
    local f base ver line
    for f in "$PKG_DB"/*.meta; do
        [ -e "$f" ] || continue
        base="${f##*/}"
        base="${base%.meta}"
        ver=""
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in
                version=*) ver="${line#version=}"; break ;;
            esac
        done < "$f"
        printf '%s %s\n' "$base" "$ver"
    done
}

db_owner() {
    [ "$#" -ge 1 ] || return 1
    grep -rlF -- "$1" "$PKG_DB"/*.files 2>/dev/null | while read -r f; do basename "$f" .files; done
}

db_sync_dpkg() {
    local status="${PREFIX}/var/lib/dpkg/status"
    [ -f "$status" ] || return 0
    ensure_dirs
    local pkg="" ver="" arch=""
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            Package:*) pkg="${line#Package: }"; pkg="$(printf '%s' "$pkg" | tr -d ' \r\n\t')" ;;
            Version:*) ver="${line#Version: }"; ver="$(printf '%s' "$ver" | tr -d ' \r\n\t')" ;;
            Architecture:*) arch="${line#Architecture: }"; arch="$(printf '%s' "$arch" | tr -d ' \r\n\t')" ;;
            Status:*installed)
                if [ -n "$pkg" ] && [ -n "$ver" ] && ! db_exists "$pkg"; then
                    db_put "$pkg" "$ver" "${arch:-aarch64}" </dev/null
                fi
                ;;
            "") pkg=""; ver=""; arch="" ;;
        esac
    done < "$status"
}
