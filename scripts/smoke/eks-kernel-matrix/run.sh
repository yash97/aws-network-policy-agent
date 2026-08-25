#!/usr/bin/env bash
set -euo pipefail

REGION="${AWS_REGION:-us-west-2}"
RELEASE_URL="https://github.com/awslabs/amazon-eks-ami/releases/tag"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

for cmd in aws curl jq awk; do
    command -v "$cmd" >/dev/null || { echo "missing dependency: $cmd" >&2; exit 1; }
done

kernel_from_release() {
    local file="$1" version="$2"
    awk -v target="$version" '
        function value(line) {
            gsub(/<[^>]*>/, "", line)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
            return line
        }
        index($0, "<summary><b>Kubernetes " target "</b></summary>") { section=1; next }
        section && /<summary><b>Kubernetes / { exit }
        section && /<th>Package<\/th>/ { header=1; column=0; next }
        header && /<\/tr>/ { header=0; next }
        header && /<th>/ {
            column++
            if (value($0) == "AL2023_x86_64_STANDARD") standard=column
            next
        }
        section && standard && /<td>kernel[^<]*<\/td>/ { row=1; column=0; next }
        row && /<\/tr>/ { row=0; next }
        row && /<td/ {
            span=1
            if (match($0, /colspan="[0-9]+"/)) {
                text=substr($0, RSTART, RLENGTH); gsub(/[^0-9]/, "", text); span=text+0
            }
            cell=value($0)
            if (column < standard && column+span >= standard && cell ~ /^[0-9]+\.[0-9]+\./) {
                print cell; exit
            }
            column+=span
        }
    ' "$file"
}

versions_json=$(aws eks describe-cluster-versions --region "$REGION" --output json)
mapfile -t versions < <(jq -r '
    [.clusterVersions[]
     | ((.versionStatus // .status) | ascii_upcase | gsub("-"; "_")) as $status
     | select($status == "STANDARD_SUPPORT" or $status == "EXTENDED_SUPPORT")
     | .clusterVersion]
    | sort_by(split(".") | map(tonumber))[]
' <<<"$versions_json")

catalog="$tmp/catalog.jsonl"
: >"$catalog"
for version in "${versions[@]}"; do
    metadata=$(aws ssm get-parameter \
        --name "/aws/service/eks/optimized-ami/$version/amazon-linux-2023/x86_64/standard/recommended" \
        --region "$REGION" --query Parameter.Value --output text)
    image_id=$(jq -er .image_id <<<"$metadata")
    image_name=$(jq -er .image_name <<<"$metadata")
    release_version=$(jq -er .release_version <<<"$metadata")
    [[ "$image_name" =~ -v([0-9]{8})$ ]] || { echo "unexpected AMI name: $image_name" >&2; exit 1; }

    tag="v${BASH_REMATCH[1]}"
    release="$tmp/$tag.html"
    [[ -s "$release" ]] || curl -fsSL "$RELEASE_URL/$tag" -o "$release"
    kernel=$(kernel_from_release "$release" "$version")
    [[ -n "$kernel" ]] || { echo "kernel not found for Kubernetes $version in $tag" >&2; exit 1; }
    kernel_line=$(cut -d. -f1,2 <<<"$kernel")

    jq -cn \
        --arg kubernetes_version "$version" \
        --arg kernel_line "$kernel_line" \
        --arg kernel_version "$kernel" \
        --arg image_id "$image_id" \
        --arg release_version "$release_version" \
        '{kubernetes_version:$kubernetes_version,kernel_line:$kernel_line,
          kernel_version:$kernel_version,image_id:$image_id,
          release_version:$release_version}' >>"$catalog"
done

jq -s '
    group_by(.kernel_line)
    | map(min_by(.kubernetes_version | split(".") | map(tonumber)))
    | sort_by(.kernel_line | split(".") | map(tonumber))
' "$catalog"
