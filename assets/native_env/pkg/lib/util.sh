#!/data/user/0/com.agyru.t2/files/usr/bin/bash
# util.sh -- shared helpers for pkg.

PKG_VERSION="0.1.0"

: "${PREFIX:?PREFIX must be exported by the AGY shell profile or pkg wrapper}"
PKG_ROOT="${PKG_ROOT:-$PREFIX/var/lib/pkg}"
PKG_DB="$PKG_ROOT/installed"
PKG_CACHE="$PKG_ROOT/cache"
PKG_INDEX="$PKG_ROOT/index"
PKG_ETC="$PREFIX/etc/pkg"

# TLS trust: the overlay ships the bundle at $PREFIX/etc/tls/cert.pem. Termux's
# curl is compiled with a /data/data/com.termux/... default, so point it at ours.
PKG_CERT="$PREFIX/etc/tls/cert.pem"
export SSL_CERT_FILE="$PKG_CERT"
export CURL_CA_BUNDLE="$PKG_CERT"
export OPENSSL_CONF="${OPENSSL_CONF:-$PREFIX/etc/tls/openssl.cnf}"

log()  { printf 'pkg: %s\n' "$*" >&2; }
warn() { printf 'pkg: warn: %s\n' "$*" >&2; }
die()  { printf 'pkg: error: %s\n' "$*" >&2; exit 1; }

ensure_dirs() { mkdir -p "$PKG_DB" "$PKG_CACHE" "$PKG_INDEX" "$PKG_ROOT/tmp"; }

# rewrite_prefix [FILES_OR_DIRS...] -- rewrite legacy /data/data and modern
# /data/user/<id> app-private paths to the active $PREFIX. Every occurrence is
# replaced, not only the shebang, so helper bodies and generated .list files
# work after extraction. Text-only, no symlink traversal, idempotent.
# Accepts file/dir paths as arguments, or list of file paths via stdin (newline
# or null-separated). If no targets are provided or stdin is empty, scans $PREFIX.
rewrite_prefix() {
    local f esc pattern='/data/(data|user/[0-9]+)/[^/]*/files/usr'
    # Escape sed-replacement metacharacters in $PREFIX (never expected, cheap).
    esc="$(printf '%s' "$PREFIX" | sed 's/[\\&@]/\\&/g')"

    local targets=("$@")
    if [ "${#targets[@]}" -eq 0 ]; then
        if [ ! -t 0 ]; then
            # Read targets from stdin
            local item
            while IFS= read -r item; do
                [ -n "$item" ] && targets+=("$item")
            done
        fi
    fi

    # Fall back to $PREFIX if no arguments and stdin was empty
    if [ "${#targets[@]}" -eq 0 ]; then
        targets=("$PREFIX")
    fi

    # Separate existing regular files from directories/other
    local files=() dirs=() t
    for t in "${targets[@]}"; do
        if [ -f "$t" ] && [ ! -L "$t" ]; then
            files+=("$t")
        elif [ -d "$t" ]; then
            dirs+=("$t")
        elif [ -e "$t" ]; then
            # Symlink or special file, skip
            continue
        fi
    done

    # 1. Process explicit regular files directly
    if [ "${#files[@]}" -gt 0 ]; then
        grep -IlZ -E -e "$pattern" -- "${files[@]}" 2>/dev/null \
            | while IFS= read -r -d '' f; do
                sed -i -E "s@$pattern@$esc@g" "$f" 2>/dev/null || true
            done
    fi

    # 2. Process directories recursively
    if [ "${#dirs[@]}" -gt 0 ]; then
        grep -rIlZ -E -e "$pattern" -- "${dirs[@]}" 2>/dev/null \
            | while IFS= read -r -d '' f; do
                sed -i -E "s@$pattern@$esc@g" "$f" 2>/dev/null || true
            done
    fi
}


load_conf() {
    [ -f "$PKG_ETC/repo.conf" ] && . "$PKG_ETC/repo.conf"
    : "${PKG_REPOS:=https://packages.termux.dev/apt/termux-main}"
    : "${PKG_CHANNEL:=stable}"
    : "${PKG_COMPONENT:=main}"
    : "${PKG_ARCH:=aarch64}"
    # data.tar paths are ./data/user/0/com.agyru.t2/files/usr/... -> 6 components.
    # deb_files strips by component count, not by a hardcoded prefix string.
    : "${PKG_DEB_STRIP:=6}"
}
