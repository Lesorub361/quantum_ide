# index.awk -- parse Debian/APT Packages stanzas into TSV.
# Output columns:
#   Package Version Architecture Essential Depends Pre-Depends Provides Conflicts Filename Size SHA256
function reset() { pkg="";ver="";arch="";ess="";dep="";pdep="";prov="";conf="";fn="";size="";sha="";last="" }
function emit() {
    if (pkg == "") return
    gsub(/\t/, " ", dep); gsub(/\t/, " ", pdep); gsub(/\t/, " ", prov); gsub(/\t/, " ", conf)
    print pkg "\t" ver "\t" arch "\t" ess "\t" dep "\t" pdep "\t" prov "\t" conf "\t" fn "\t" size "\t" sha
}
function appendv(k, v) {
    if (k == "Depends") dep = dep " " v
    else if (k == "Pre-Depends") pdep = pdep " " v
    else if (k == "Provides") prov = prov " " v
    else if (k == "Conflicts") conf = conf " " v
}
function setf(k, v) {
    if (k == "Package") pkg = v
    else if (k == "Version") ver = v
    else if (k == "Architecture") arch = v
    else if (k == "Essential") ess = v
    else if (k == "Depends") dep = v
    else if (k == "Pre-Depends") pdep = v
    else if (k == "Provides") prov = v
    else if (k == "Conflicts") conf = v
    else if (k == "Filename") fn = v
    else if (k == "Size") size = v
    else if (k == "SHA256") sha = v
    last = k
}
/^[ \t]/ { if (last != "") appendv(last, substr($0, 2)); next }
$0 == "" { emit(); reset(); next }
{
    c = index($0, ":")
    if (c == 0) next
    k = substr($0, 1, c - 1)
    v = substr($0, c + 1); sub(/^[ \t]/, "", v)
    setf(k, v)
}
END { emit() }
