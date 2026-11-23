#!/data/user/0/com.agyru.t2/files/usr/bin/bash
# deb.sh -- read .deb (ar archive) + extract members. No `ar` dependency.
# Uses dd/tail/head for ar, tar for payloads, and xz/gzip/zstd/bzip2 by suffix.

# ar_members FILE -> member names
ar_members() {
    local file="$1" off=8 hdr name size data
    while :; do
        hdr="$(dd if="$file" bs=1 skip="$off" count=60 2>/dev/null)"
        [ "${#hdr}" -ge 58 ] || break
        name="$(printf '%s' "$hdr" | cut -c1-16 | sed 's/[[:space:]]*$//; s:/$::')"
        size="$(printf '%s' "$hdr" | cut -c49-58 | sed 's/ //g')"
        [ -n "$name" ] && [ -n "$size" ] || break
        printf '%s\n' "$name"
        data=$((off + 60))
        off=$((data + size + (size % 2)))
    done
}

# ar_member FILE NAME -> raw member bytes on stdout
ar_member() {
    local file="$1" want="$2" off=8 hdr name size data
    while :; do
        hdr="$(dd if="$file" bs=1 skip="$off" count=60 2>/dev/null)"
        [ "${#hdr}" -ge 58 ] || return 1
        name="$(printf '%s' "$hdr" | cut -c1-16 | sed 's/[[:space:]]*$//; s:/$::')"
        size="$(printf '%s' "$hdr" | cut -c49-58 | sed 's/ //g')"
        [ -n "$size" ] || return 1
        data=$((off + 60))
        if [ "$name" = "$want" ]; then
            tail -c +$((data + 1)) "$file" | head -c "$size"
            return 0
        fi
        off=$((data + size + (size % 2)))
    done
}

deb_decode() { # NAME  (reads stdin)
    case "$1" in
        *.xz)  xz -dc ;;
        *.gz)  gzip -dc ;;
        *.zst) zstd -dc ;;
        *.bz2) bzip2 -dc ;;
        *)     cat ;;
    esac
}

deb_member_name() { # FILE control|data
    ar_members "$1" | grep -E "^$2\.tar\." | head -n 1
}

deb_field() { # FILE FIELD -> value (authoritative control)
    local f="$1" field="$2" m control_path val
    m="$(deb_member_name "$f" control)"
    [ -n "$m" ] || return 1
    control_path="$(ar_member "$f" "$m" | deb_decode "$m" | tar -tf - 2>/dev/null \
        | awk '$0 == "./control" || $0 == "control" { print; exit }')"
    [ -n "$control_path" ] || return 1
    val="$(ar_member "$f" "$m" | deb_decode "$m" \
        | tar -xOf - "$control_path" 2>/dev/null \
        | awk -v k="$field" 'index($0, k":") == 1 { sub(/^[^:]*: /, ""); print; exit }')"
    printf '%s\n' "$val"
}

deb_validate_data() { # FILE -- reject absolute/traversal/non-prefix entries
    local m
    m="$(deb_member_name "$1" data)"
    [ -n "$m" ] || return 1
    ar_member "$1" "$m" | deb_decode "$m" | tar -tf - 2>/dev/null | awk '
        {
            path = $0
            if (path == "" || substr(path, 1, 1) == "/" || index(path, "\\") > 0) {
                bad = 1; next
            }
            if (path == "./" || path == ".") next
            if (substr(path, 1, 2) != "./") { bad = 1; next }
            path = substr(path, 3)
            if (substr(path, length(path), 1) == "/") path = substr(path, 1, length(path) - 1)
            n = split(path, part, "/")
            if (part[1] != "data") { bad = 1; next }
            if (n >= 2 && part[2] != "data") { bad = 1; next }
            if (n >= 3 && part[3] !~ /^[A-Za-z0-9][A-Za-z0-9+._-]*$/) { bad = 1; next }
            if (n >= 4 && part[4] != "files") { bad = 1; next }
            if (n >= 5 && part[5] != "usr") { bad = 1; next }
            for (i = 1; i <= n; i++) if (part[i] == ".." || part[i] == ".") bad = 1
        }
        END { if (bad) exit 1 }
    '
}

deb_extract_data() { # FILE DEST [STRIP]
    local m strip="${3:-${PKG_DEB_STRIP:-6}}"
    deb_validate_data "$1" || return 1
    m="$(deb_member_name "$1" data)"
    [ -n "$m" ] || return 1
    ar_member "$1" "$m" | deb_decode "$m" | tar -x --strip-components="$strip" -C "$2" 2>/dev/null
}

deb_files() { # FILE -> relative paths under the stripped data prefix
    local m strip="${PKG_DEB_STRIP:-6}"
    deb_validate_data "$1" || return 1
    m="$(deb_member_name "$1" data)"
    [ -n "$m" ] || return 1
    # Strip the leading N path components by position instead of matching a
    # hardcoded prefix string. The data prefix is the foreign (Termux) prefix
    # but has the same depth as ours, and the rewrite pass repoints every
    # occurrence of the foreign prefix -- including this file -- so matching a
    # literal here would break after installation.
    ar_member "$1" "$m" | deb_decode "$m" \
        | tar -t 2>/dev/null \
        | awk -v s="$strip" -F/ '{
              n = NF
              if (n > 0 && $n == "") n--
              if (n <= s) next
              out = ""
              for (i = s + 1; i <= n; i++) out = out (i > s + 1 ? "/" : "") $i
              print out
          }' \
        | grep -v '^$' | sort -u
}
