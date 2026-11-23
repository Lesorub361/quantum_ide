# vercmp.awk -- Debian version comparison (dpkg semantics).
# usage: awk -v a=VER -v b=VER -f vercmp.awk
# prints -1 | 0 | 1
#
# Rules: epoch:upstream-revision. Non-digit chars: '~' sorts before
# empty, empty before letters, letters before other chars.
function ord(c) {
    if (c == "") return 0
    if (c == "~") return -1
    if (c ~ /[A-Za-z]/) return index(ORD, c)
    return index(ORD, c) + 256
}
function verrevcmp(s, t,    i, j, la, lb, ca, cb, oa, ob, da, db) {
    la = length(s); lb = length(t); i = 1; j = 1
    while (i <= la || j <= lb) {
        while ((i <= la && substr(s, i, 1) !~ /[0-9]/) || (j <= lb && substr(t, j, 1) !~ /[0-9]/)) {
            ca = (i <= la) ? substr(s, i, 1) : ""
            cb = (j <= lb) ? substr(t, j, 1) : ""
            if (ca == "" && cb == "") break
            oa = ord(ca); ob = ord(cb)
            if (oa != ob) return (oa < ob) ? -1 : 1
            i++; j++
        }
        while (i <= la && substr(s, i, 1) == "0") i++
        while (j <= lb && substr(t, j, 1) == "0") j++
        da = ""; while (i <= la && substr(s, i, 1) ~ /[0-9]/) { da = da substr(s, i, 1); i++ }
        db = ""; while (j <= lb && substr(t, j, 1) ~ /[0-9]/) { db = db substr(t, j, 1); j++ }
        if (length(da) != length(db)) return (length(da) < length(db)) ? -1 : 1
        if (da != db) return (da < db) ? -1 : 1
    }
    return 0
}
function last_dash(s,    k, p) { p = 0; for (k = 1; k <= length(s); k++) if (substr(s, k, 1) == "-") p = k; return p }
function debcmp(x, y,    i, ea, eb, ua, ub, ra, rb, r) {
    ea = "0"; eb = "0"
    if ((i = index(x, ":")) > 0) { ea = substr(x, 1, i - 1); x = substr(x, i + 1) }
    if ((i = index(y, ":")) > 0) { eb = substr(y, 1, i - 1); y = substr(y, i + 1) }
    if ((ea + 0) != (eb + 0)) return ((ea + 0) < (eb + 0)) ? -1 : 1
    if ((i = last_dash(x)) > 0) { ua = substr(x, 1, i - 1); ra = substr(x, i + 1) } else { ua = x; ra = "" }
    if ((i = last_dash(y)) > 0) { ub = substr(y, 1, i - 1); rb = substr(y, i + 1) } else { ub = y; rb = "" }
    r = verrevcmp(ua, ub); if (r != 0) return r
    return verrevcmp(ra, rb)
}
BEGIN {
    for (i = 1; i < 256; i++) ORD = ORD sprintf("%c", i)
    print debcmp(a, b)
    exit
}
