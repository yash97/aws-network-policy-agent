#!/usr/bin/env bash
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"

cat >"$tmp/bin/aws" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1 $2" == "eks describe-cluster-versions" ]]; then
    cat <<'JSON'
{"clusterVersions":[
 {"clusterVersion":"1.36","versionStatus":"STANDARD_SUPPORT"},
 {"clusterVersion":"1.34","status":"standard-support"},
 {"clusterVersion":"1.33","status":"extended-support"},
 {"clusterVersion":"1.32","versionStatus":"EXTENDED_SUPPORT"},
 {"clusterVersion":"1.30","versionStatus":"UNSUPPORTED"}]}
JSON
elif [[ "$1 $2" == "ssm get-parameter" ]]; then
    while [[ $# -gt 0 ]]; do
        [[ "$1" == "--name" ]] && { name="$2"; break; }
        shift
    done
    version=$(sed -n 's#.*optimized-ami/\([0-9]*\.[0-9]*\)/.*#\1#p' <<<"$name")
    [[ "$version" != "1.30" ]] || exit 1
    printf '{"image_id":"ami-%s","image_name":"amazon-eks-node-al2023-x86_64-standard-%s-v20260818","release_version":"%s-test"}\n' \
        "${version/./}" "$version" "$version"
else
    echo "unexpected aws command: $*" >&2; exit 1
fi
EOF
chmod +x "$tmp/bin/aws"

cat >"$tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
while [[ $# -gt 0 ]]; do
    [[ "$1" == "-o" ]] && { output="$2"; shift 2; continue; }
    shift
done
header() {
    cat <<'HTML'
<tr>
<th>Package</th>
<th>AL2023_x86_64_NVIDIA</th>
<th>AL2023_x86_64_NEURON</th>
<th>AL2023_x86_64_STANDARD</th>
<th>AL2023_ARM_64_NVIDIA</th>
<th>AL2023_ARM_64_STANDARD</th>
</tr>
HTML
}
{
    echo '<summary><b>Kubernetes 1.36</b></summary>'; header
    cat <<'HTML'
<tr><td>kernel6.18</td>
<td colspan="2">9.9.9-wrong-variant</td>
<td>6.18.41-94.142.amzn2023</td>
<td colspan="2">8.8.8-other-variant</td>
</tr>
HTML
    echo '<summary><b>Kubernetes 1.34</b></summary>'; header
    printf '<tr><td>kernel6.12</td>\n<td colspan="5">6.12.100-125.179.amzn2023</td>\n</tr>\n'
    echo '<summary><b>Kubernetes 1.33</b></summary>'; header
    printf '<tr><td>kernel6.12</td>\n<td colspan="5">6.12.99-1.amzn2023</td>\n</tr>\n'
    echo '<summary><b>Kubernetes 1.32</b></summary>'; header
    printf '<tr><td>kernel</td>\n<td colspan="3">6.1.180-225.360.amzn2023</td>\n</tr>\n'
} >"$output"
EOF
chmod +x "$tmp/bin/curl"

result=$(PATH="$tmp/bin:$PATH" "$DIR/run.sh")
jq -e '
    map(.kernel_line) == ["6.1","6.12","6.18"] and
    map(.kubernetes_version) == ["1.32","1.33","1.36"] and
    .[1].kernel_version == "6.12.99-1.amzn2023"
' <<<"$result" >/dev/null

echo "PASS: kernel matrix discovery"
