#!/data/user/0/com.agyru.t2/files/usr/bin/bash
# index.sh -- Packages index helpers.
# Requires PKG_LIB, PKG_INDEX, deb_gt (version.sh).

# index_parse FILE -> TSV (see index.awk for columns)
index_parse() { awk -f "$PKG_LIB/index.awk" "$1"; }

# index_rebuild FILE.Packages -> writes FILE.tsv
index_rebuild() {
    [ -f "$1" ] || return 1
    awk -f "$PKG_LIB/index.awk" "$1" > "${1%.Packages}.tsv"
}

index_rebuild_all() {
    local f
    for f in "$PKG_INDEX"/repo.*.Packages; do
        [ -e "$f" ] || continue
        index_rebuild "$f"
    done
}

index_tsvs() { ls "$PKG_INDEX"/repo.*.tsv 2>/dev/null; }

# index_lookup NAME -> "repo.N<TAB>line" of the highest version (all repos)
index_lookup() {
    local name="$1" tsv base line v best="" bestver=""
    for tsv in $(index_tsvs); do
        base="$(basename "$tsv" .tsv)"
        while IFS= read -r line; do
            v="$(printf '%s' "$line" | cut -f2)"
            if [ -z "$bestver" ] || deb_gt "$v" "$bestver"; then
                bestver="$v"; best="$base	$line"
            fi
        done < <(awk -F'\t' -v n="$name" '$1 == n' "$tsv")
    done
    [ -n "$best" ] && printf '%s\n' "$best"
}

# index_provider NAME -> "repo.N<TAB>line" of a package whose Provides has NAME
index_provider() {
    local name="$1" tsv base line
    for tsv in $(index_tsvs); do
        base="$(basename "$tsv" .tsv)"
        while IFS= read -r line; do
            printf '%s\t%s\n' "$base" "$line"; return 0
        done < <(awk -F'\t' -v n="$name" '{
            c = split($7, a, ",")
            for (i = 1; i <= c; i++) { gsub(/ /, "", a[i]); if (a[i] == n) { print; exit } }
        }' "$tsv")
    done
}

# E1 compat
index_get() { index_parse "$1" | awk -F'\t' -v n="$2" -v c="$3" '$1 == n { print $c }' | tail -n 1; }
index_best() { index_parse "$1" | awk -F'\t' -v n="$2" '$1 == n'; }
