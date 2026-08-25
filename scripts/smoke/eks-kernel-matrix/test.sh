#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=cluster-name.sh
source "$SCRIPT_DIR/cluster-name.sh"
# shellcheck source=kernel-verification.sh
source "$SCRIPT_DIR/kernel-verification.sh"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

MOCK_BIN="$TEMP_DIR/bin"
mkdir -p "$MOCK_BIN"

cat >"$TEMP_DIR/cluster-versions.json" <<'JSON'
{
  "clusterVersions": [
    {"clusterVersion":"1.36","versionStatus":"STANDARD_SUPPORT","endOfExtendedSupportDate":"2028-08-02T00:00:00+00:00"},
    {"clusterVersion":"1.35","status":"standard-support","endOfExtendedSupportDate":"2028-03-27T00:00:00+00:00"},
    {"clusterVersion":"1.34","versionStatus":"STANDARD_SUPPORT"},
    {"clusterVersion":"1.33","status":"extended-support","endOfExtendedSupportDate":"2027-07-29T00:00:00+00:00"},
    {"clusterVersion":"1.32","versionStatus":"EXTENDED_SUPPORT","endOfExtendedSupportDate":"2027-03-23T00:00:00+00:00"},
    {"clusterVersion":"1.31","status":"extended-support","endOfExtendedSupportDate":"2026-11-26T00:00:00+00:00"},
    {"clusterVersion":"1.30","versionStatus":"UNSUPPORTED","endOfExtendedSupportDate":"2026-07-23T00:00:00+00:00"}
  ]
}
JSON

write_package_header_standard_second() {
    cat <<'HTML'
<tr>
  <th>Package</th>
  <th>AL2023_x86_64_NVIDIA</th>
  <th>AL2023_x86_64_STANDARD</th>
  <th>AL2023_x86_64_NEURON</th>
  <th>AL2023_ARM_64_NVIDIA</th>
  <th>AL2023_ARM_64_STANDARD</th>
</tr>
HTML
}

write_package_header_standard_fourth() {
    cat <<'HTML'
<tr>
  <th>Package</th>
  <th>AL2023_x86_64_NVIDIA</th>
  <th>AL2023_x86_64_NEURON</th>
  <th>AL2023_ARM_64_NVIDIA</th>
  <th>AL2023_x86_64_STANDARD</th>
  <th>AL2023_ARM_64_STANDARD</th>
</tr>
HTML
}

{
    echo '<summary><b>Kubernetes 1.36</b></summary>'
    write_package_header_standard_fourth
    cat <<'HTML'
<tr>
  <td>kernel6.18</td>
  <td colspan="3">9.9.9-wrong-column</td>
  <td colspan="1">6.18.41-94.142.amzn2023</td>
  <td colspan="1">8.8.8-wrong-column</td>
</tr>
HTML
    echo '<summary><b>Kubernetes 1.35</b></summary>'
    write_package_header_standard_second
    cat <<'HTML'
<tr>
  <td>kernel6.12</td>
  <td colspan="5">6.12.100-125.179.amzn2023</td>
</tr>
HTML
    echo '<summary><b>Kubernetes 1.34</b></summary>'
    write_package_header_standard_second
    cat <<'HTML'
<tr>
  <td>kernel6.12</td>
  <td colspan="5">6.12.100-125.179.amzn2023</td>
</tr>
HTML
    echo '<summary><b>Kubernetes 1.33</b></summary>'
    write_package_header_standard_second
    cat <<'HTML'
<tr>
  <td>kernel6.12</td>
  <td colspan="5">6.12.100-125.179.amzn2023</td>
</tr>
HTML
    echo '<summary><b>Kubernetes 1.32</b></summary>'
    write_package_header_standard_second
    cat <<'HTML'
<tr>
  <td>kernel</td>
  <td colspan="2">6.1.180-225.360.amzn2023</td>
  <td colspan="1">—</td>
  <td colspan="1">6.12.100-125.179.amzn2023</td>
  <td colspan="1">6.1.180-225.360.amzn2023</td>
</tr>
<tr>
  <td>kernel6.12</td>
  <td colspan="3">—</td>
  <td colspan="1">6.12.100-125.179.amzn2023</td>
  <td colspan="1">—</td>
</tr>
HTML
    echo '<summary><b>Kubernetes 1.31</b></summary>'
    write_package_header_standard_second
    cat <<'HTML'
<tr>
  <td>kernel</td>
  <td colspan="2">6.1.180-225.360.amzn2023</td>
  <td colspan="1">—</td>
  <td colspan="1">6.12.100-125.179.amzn2023</td>
  <td colspan="1">6.1.180-225.360.amzn2023</td>
</tr>
<tr>
  <td>kernel6.12</td>
  <td colspan="3">—</td>
  <td colspan="1">6.12.100-125.179.amzn2023</td>
  <td colspan="1">—</td>
</tr>
HTML
} >"$TEMP_DIR/release-body.html"

cat >"$MOCK_BIN/aws" <<'MOCK_AWS'
#!/usr/bin/env bash
set -euo pipefail

service="${1:-}"
operation="${2:-}"
shift 2
expected_region="${MOCK_REGION:-us-west-2}"

unexpected_argument() {
    echo "Unexpected argument for $service $operation: $1" >&2
    exit 1
}

require_equal() {
    local name="$1"
    local actual="$2"
    local expected="$3"
    if [[ "$actual" != "$expected" ]]; then
        echo "Unexpected $name for $service $operation: '$actual' (expected '$expected')" >&2
        exit 1
    fi
}

case "$service:$operation" in
    eks:describe-cluster-versions)
        if [[ "${MOCK_EKS_FAILURE:-false}" == "true" ]]; then
            echo "mock EKS discovery failure" >&2
            exit 42
        fi
        region=""
        output=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --region)
                    region="$2"
                    shift 2
                    ;;
                --output)
                    output="$2"
                    shift 2
                    ;;
                *)
                    unexpected_argument "$1"
                    ;;
            esac
        done
        require_equal region "$region" "$expected_region"
        require_equal output "$output" json
        cat "$MOCK_CLUSTER_VERSIONS"
        ;;
    ssm:get-parameter)
        parameter_name=""
        region=""
        query=""
        output=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --name)
                    parameter_name="$2"
                    shift 2
                    ;;
                --region)
                    region="$2"
                    shift 2
                    ;;
                --query)
                    query="$2"
                    shift 2
                    ;;
                --output)
                    output="$2"
                    shift 2
                    ;;
                *)
                    unexpected_argument "$1"
                    ;;
            esac
        done
        require_equal region "$region" "$expected_region"
        require_equal query "$query" Parameter.Value
        require_equal output "$output" text
        if [[ ! "$parameter_name" =~ optimized-ami/([0-9]+\.[0-9]+)/ ]]; then
            echo "Unexpected parameter: $parameter_name" >&2
            exit 1
        fi
        version="${BASH_REMATCH[1]}"
        if [[ "$version" == "1.30" ]]; then
            echo "Unsupported Kubernetes version was queried" >&2
            exit 1
        fi
        if [[ "${MOCK_SSM_MODE:-valid}" == "malformed" ]]; then
            printf '{}\n'
            exit 0
        fi
        patch="${version/./}"
        printf '{"schema_version":"2","image_id":"ami-%017d","image_name":"amazon-eks-node-al2023-x86_64-standard-%s-v20260818","release_version":"%s.0-20260818"}\n' \
            "$patch" "$version" "$version"
        ;;
    ec2:describe-images)
        image_id=""
        region=""
        query=""
        output=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --image-ids)
                    image_id="$2"
                    shift 2
                    ;;
                --region)
                    region="$2"
                    shift 2
                    ;;
                --query)
                    query="$2"
                    shift 2
                    ;;
                --output)
                    output="$2"
                    shift 2
                    ;;
                *)
                    unexpected_argument "$1"
                    ;;
            esac
        done
        require_equal region "$region" "$expected_region"
        require_equal query "$query" 'Images[0].State'
        require_equal output "$output" text
        if [[ -z "$image_id" ]]; then
            echo "Missing image ID" >&2
            exit 1
        fi
        printf '%s\n' "${MOCK_IMAGE_STATE:-available}"
        ;;
    *)
        echo "Unexpected AWS command: $service $operation" >&2
        exit 1
        ;;
esac
MOCK_AWS
chmod +x "$MOCK_BIN/aws"

cat >"$MOCK_BIN/curl" <<'MOCK_CURL'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${MOCK_CURL_FAILURE:-false}" == "true" ]]; then
    echo "mock GitHub failure" >&2
    exit 42
fi
url="${*: -1}"
if [[ "$url" != */v20260818 ]]; then
    echo "Unexpected release URL: $url" >&2
    exit 1
fi
case "$url" in
    https://api.github.com/*)
        jq -Rs '{body: .}' "$MOCK_RELEASE_BODY"
        ;;
    https://github.com/*/releases/tag/*)
        cat "$MOCK_RELEASE_BODY"
        ;;
    *)
        echo "Unexpected release URL: $url" >&2
        exit 1
        ;;
esac
MOCK_CURL
chmod +x "$MOCK_BIN/curl"

run_discovery() {
    local statuses="${1:-STANDARD_SUPPORT,EXTENDED_SUPPORT}"
    local cluster_versions="${2:-$TEMP_DIR/cluster-versions.json}"
    local release_body="${3:-$TEMP_DIR/release-body.html}"
    local image_state="${4:-available}"
    local catalog_output="${5:-}"
    local eks_failure="${6:-false}"
    local ssm_mode="${7:-valid}"
    local curl_failure="${8:-false}"
    local github_token="${9-mock-token}"

    MOCK_CLUSTER_VERSIONS="$cluster_versions" \
    MOCK_RELEASE_BODY="$release_body" \
    MOCK_IMAGE_STATE="$image_state" \
    MOCK_EKS_FAILURE="$eks_failure" \
    MOCK_SSM_MODE="$ssm_mode" \
    MOCK_CURL_FAILURE="$curl_failure" \
    GITHUB_TOKEN="$github_token" \
    EKS_SUPPORT_STATUSES="$statuses" \
    AWS_BIN="$MOCK_BIN/aws" \
    CURL_BIN="$MOCK_BIN/curl" \
    OUTPUT_FORMAT=json \
    CATALOG_OUTPUT_FILE="$catalog_output" \
    "$SCRIPT_DIR/run.sh"
}

catalog_output="$TEMP_DIR/catalog-output.json"
all_supported=$(run_discovery \
    STANDARD_SUPPORT,EXTENDED_SUPPORT \
    "$TEMP_DIR/cluster-versions.json" \
    "$TEMP_DIR/release-body.html" \
    available \
    "$catalog_output")
jq -e '
    length == 3
    and map(.kernel_line) == ["6.1", "6.12", "6.18"]
    and map(.kubernetes_version) == ["1.31", "1.33", "1.36"]
    and map(.support_status) == ["EXTENDED_SUPPORT", "EXTENDED_SUPPORT", "STANDARD_SUPPORT"]
    and .[0].kernel_version == "6.1.180-225.360.amzn2023"
    and .[1].kernel_version == "6.12.100-125.179.amzn2023"
    and .[2].kernel_version == "6.18.41-94.142.amzn2023"
' <<<"$all_supported" >/dev/null
jq -e '
    map(select(.kubernetes_version == "1.34"))[0].end_of_extended_support == null
' "$catalog_output" >/dev/null

release_page_output=$(run_discovery \
    STANDARD_SUPPORT,EXTENDED_SUPPORT \
    "$TEMP_DIR/cluster-versions.json" \
    "$TEMP_DIR/release-body.html" \
    available "" false valid false "")
jq -e '
    map(.kernel_line) == ["6.1", "6.12", "6.18"]
' <<<"$release_page_output" >/dev/null

standard_support_only=$(run_discovery STANDARD_SUPPORT)
jq -e '
    length == 2
    and map(.kernel_line) == ["6.12", "6.18"]
    and map(.kubernetes_version) == ["1.34", "1.36"]
    and map(.support_status) == ["STANDARD_SUPPORT", "STANDARD_SUPPORT"]
' <<<"$standard_support_only" >/dev/null

if unavailable_error=$(run_discovery \
    STANDARD_SUPPORT,EXTENDED_SUPPORT \
    "$TEMP_DIR/cluster-versions.json" \
    "$TEMP_DIR/release-body.html" \
    failed 2>&1); then
    echo "FAIL: unavailable AMI was accepted" >&2
    exit 1
fi
grep -Fq 'is not available' <<<"$unavailable_error"

sed 's/AL2023_x86_64_STANDARD/AL2023_x86_64_OTHER/g' \
    "$TEMP_DIR/release-body.html" >"$TEMP_DIR/missing-standard-header.html"
if missing_header_error=$(run_discovery \
    STANDARD_SUPPORT,EXTENDED_SUPPORT \
    "$TEMP_DIR/cluster-versions.json" \
    "$TEMP_DIR/missing-standard-header.html" 2>&1); then
    echo "FAIL: missing AL2023 standard header was accepted" >&2
    exit 1
fi
grep -Fq 'Unable to find the AL2023 x86_64 standard kernel' <<<"$missing_header_error"

if unsupported_status_error=$(
    EKS_SUPPORT_STATUSES=UNSUPPORTED \
    OUTPUT_FORMAT=json \
    AWS_BIN=/bin/false \
    CURL_BIN=/bin/false \
    "$SCRIPT_DIR/run.sh" 2>&1
); then
    echo "FAIL: unsupported EKS support status was accepted" >&2
    exit 1
fi
grep -Fq 'Unsupported EKS support status: UNSUPPORTED' <<<"$unsupported_status_error"

if eks_error=$(run_discovery \
    STANDARD_SUPPORT,EXTENDED_SUPPORT \
    "$TEMP_DIR/cluster-versions.json" \
    "$TEMP_DIR/release-body.html" \
    available "" true 2>&1); then
    echo "FAIL: EKS discovery failure was accepted" >&2
    exit 1
fi
grep -Fq 'Failed to discover supported EKS Kubernetes versions' <<<"$eks_error"

if ssm_error=$(run_discovery \
    STANDARD_SUPPORT,EXTENDED_SUPPORT \
    "$TEMP_DIR/cluster-versions.json" \
    "$TEMP_DIR/release-body.html" \
    available "" false malformed 2>&1); then
    echo "FAIL: malformed SSM metadata was accepted" >&2
    exit 1
fi
grep -Fq 'Malformed SSM AMI metadata' <<<"$ssm_error"

if github_error=$(run_discovery \
    STANDARD_SUPPORT,EXTENDED_SUPPORT \
    "$TEMP_DIR/cluster-versions.json" \
    "$TEMP_DIR/release-body.html" \
    available "" false valid true 2>&1); then
    echo "FAIL: GitHub retrieval failure was accepted" >&2
    exit 1
fi
grep -Fq 'Failed to retrieve EKS AMI release metadata' <<<"$github_error"

if format_error=$(
    OUTPUT_FORMAT=yaml \
    AWS_BIN=/bin/false \
    CURL_BIN=/bin/false \
    "$SCRIPT_DIR/run.sh" 2>&1
); then
    echo "FAIL: invalid output format was accepted" >&2
    exit 1
fi
grep -Fq 'Unsupported OUTPUT_FORMAT: yaml' <<<"$format_error"

verify_node_kernel_versions \
    '6.12.100-125.179.amzn2023' \
    '6.12.100-125.179.amzn2023.x86_64' \
    '6.12.100-125.179.amzn2023.x86_64'

if kernel_error=$(verify_node_kernel_versions \
    '6.12.100-125.179.amzn2023' \
    '6.12.101-126.180.amzn2023.x86_64' 2>&1); then
    echo "FAIL: wrong kernel patch within the expected line was accepted" >&2
    exit 1
fi
grep -Fq 'Expected kernel 6.12.100-125.179.amzn2023 on every node' <<<"$kernel_error"

GITHUB_RUN_ATTEMPT=1 cluster_name_attempt_one=$(
    nightly_kernel_cluster_name '6.12' 'IPv6' '123456'
)
GITHUB_RUN_ATTEMPT=2 cluster_name_attempt_two=$(
    nightly_kernel_cluster_name '6.12' 'IPv6' '123456'
)
if [[ "$cluster_name_attempt_one" != "$cluster_name_attempt_two" ]] \
    || [[ "$cluster_name_attempt_one" != 'npa-nightly-k6-12-ipv6-123456' ]]; then
    echo "FAIL: cluster name changed across run attempts" >&2
    exit 1
fi

echo "PASS: EKS AL2023 kernel-matrix smoke test"
