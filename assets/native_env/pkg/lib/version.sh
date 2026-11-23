#!/data/user/0/com.agyru.t2/files/usr/bin/bash
# version.sh -- Debian version comparison wrappers.
# Requires PKG_LIB (dir of vercmp.awk).

deb_vercmp() { awk -v a="$1" -v b="$2" -f "$PKG_LIB/vercmp.awk"; }
deb_ge() { [ "$(deb_vercmp "$1" "$2")" != "-1" ]; }
deb_gt() { [ "$(deb_vercmp "$1" "$2")" = "1" ]; }
