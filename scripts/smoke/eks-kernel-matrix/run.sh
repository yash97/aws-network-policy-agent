#!/usr/bin/env bash

set -euo pipefail

REGION="${AWS_REGION:-${REGION:-us-west-2}}"
EKS_SUPPORT_STATUSES="${EKS_SUPPORT_STATUSES:-STANDARD_SUPPORT,EXTENDED_SUPPORT}"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-table}"
OUTPUT_FILE="${OUTPUT_FILE:-}"
CATALOG_OUTPUT_FILE="${CATALOG_OUTPUT_FILE:-}"
AWS_BIN="${AWS_BIN:-aws}"
CURL_BIN="${CURL_BIN:-curl}"
GITHUB_API_URL="${GITHUB_API_URL:-https://api.github.com/repos/awslabs/amazon-eks-ami/releases/tags}"
GITHUB_RELEASE_URL="${GITHUB_RELEASE_URL:-https://github.com/awslabs/amazon-eks-ami/releases/tag}"

case "$OUTPUT_FORMAT" in
    json|table) ;;
    *)
        echo "Unsupported OUTPUT_FORMAT: $OUTPUT_FORMAT (expected table or json)" >&2
        exit 1
        ;;
esac

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

require_command() {
    local command_name="$1"
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Required command is not installed: $command_name" >&2
        exit 1
    fi
}

fetch_release_body() {
    local release_tag="$1"
    local body_file="$TEMP_DIR/${release_tag}.body"
    local response_file="$TEMP_DIR/${release_tag}.json"

    if [[ -f "$body_file" ]]; then
        printf '%s\n' "$body_file"
        return
    fi

    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        if ! "$CURL_BIN" -fsSL "$GITHUB_RELEASE_URL/$release_tag" >"$body_file"; then
            echo "Failed to retrieve EKS AMI release metadata for $release_tag" >&2
            exit 1
        fi
        printf '%s\n' "$body_file"
        return
    fi

    local -a curl_args=(
        -fsSL
        -H "Accept: application/vnd.github+json"
        -H "X-GitHub-Api-Version: 2022-11-28"
        -H "Authorization: Bearer ${GITHUB_TOKEN}"
    )

    if ! "$CURL_BIN" "${curl_args[@]}" "$GITHUB_API_URL/$release_tag" >"$response_file"; then
        echo "Failed to retrieve EKS AMI release metadata for $release_tag" >&2
        exit 1
    fi

    if ! jq -er '.body | strings | select(length > 0)' "$response_file" >"$body_file"; then
        echo "EKS AMI release $release_tag did not contain release notes" >&2
        exit 1
    fi

    printf '%s\n' "$body_file"
}

extract_standard_x86_kernel() {
    local body_file="$1"
    local kubernetes_version="$2"

    awk -v target="$kubernetes_version" '
        function trim(value) {
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            return value
        }

        function cell_value(line, value) {
            value = line
            gsub(/<[^>]*>/, "", value)
            return trim(value)
        }

        index($0, "<summary><b>Kubernetes " target "</b></summary>") {
            in_version = 1
            next
        }

        in_version && /<summary><b>Kubernetes / {
            exit
        }

        in_version && /<th>Package<\/th>/ {
            in_package_header = 1
            header_column = 0
            target_column = 0
            next
        }

        in_package_header && /<\/tr>/ {
            in_package_header = 0
            next
        }

        in_package_header && /<th>/ {
            header_column++
            header = cell_value($0)
            if (header == "AL2023_x86_64_STANDARD") {
                if (target_column != 0) {
                    target_column = -1
                } else {
                    target_column = header_column
                }
            }
            next
        }

        in_version && target_column > 0 && /<td>kernel[^<]*<\/td>/ {
            in_kernel_row = 1
            data_column = 0
            next
        }

        in_kernel_row && /<\/tr>/ {
            in_kernel_row = 0
            next
        }

        in_kernel_row && /<td/ {
            span = 1
            if (match($0, /colspan="[0-9]+"/)) {
                span_text = substr($0, RSTART, RLENGTH)
                gsub(/[^0-9]/, "", span_text)
                span = span_text + 0
            }

            value = cell_value($0)

            # Expand colspan logically and select the kernel value covering
            # the AL2023_x86_64_STANDARD column found in the table header.
            if (data_column < target_column && data_column + span >= target_column) {
                if (value != "—" && value != "-" && value != "&mdash;") {
                    print value
                    exit
                }
            }
            data_column += span
        }
    ' "$body_file"
}

for command_name in "$AWS_BIN" "$CURL_BIN" jq awk; do
    require_command "$command_name"
done

statuses_json=$(printf '%s' "$EKS_SUPPORT_STATUSES" \
    | tr ',' '\n' \
    | jq -R 'gsub("^[[:space:]]+|[[:space:]]+$"; "") | ascii_upcase | gsub("-"; "_") | select(length > 0)' \
    | jq -s '.')

if [[ "$(jq 'length' <<<"$statuses_json")" -eq 0 ]]; then
    echo "EKS_SUPPORT_STATUSES must include at least one support status" >&2
    exit 1
fi

unsupported_statuses=$(jq -r '
    . - ["STANDARD_SUPPORT", "EXTENDED_SUPPORT"]
    | join(",")
' <<<"$statuses_json")
if [[ -n "$unsupported_statuses" ]]; then
    echo "Unsupported EKS support status: $unsupported_statuses" >&2
    exit 1
fi

if ! cluster_versions_json=$(
    "$AWS_BIN" eks describe-cluster-versions \
        --region "$REGION" \
        --output json
); then
    echo "Failed to discover supported EKS Kubernetes versions in $REGION" >&2
    exit 1
fi

if ! eligible_versions_json=$(jq -ce --argjson statuses "$statuses_json" '
    def normalized_status:
        (.versionStatus // .status // "")
        | ascii_upcase
        | gsub("-"; "_");
    [
        .clusterVersions[]
        | normalized_status as $status
        | select($statuses | index($status))
        | .clusterVersion
    ]
    | sort_by(split(".") | map(tonumber))
    | select(length > 0)
' <<<"$cluster_versions_json"); then
    echo "No EKS Kubernetes versions matched support statuses: $EKS_SUPPORT_STATUSES" >&2
    exit 1
fi

catalog_file="$TEMP_DIR/catalog.jsonl"
touch "$catalog_file"

while IFS= read -r kubernetes_version; do
    parameter_name="/aws/service/eks/optimized-ami/${kubernetes_version}/amazon-linux-2023/x86_64/standard/recommended"
    if ! ami_metadata=$(
        "$AWS_BIN" ssm get-parameter \
            --name "$parameter_name" \
            --region "$REGION" \
            --query 'Parameter.Value' \
            --output text
    ); then
        echo "Failed to resolve the recommended AL2023 AMI for Kubernetes $kubernetes_version in $REGION" >&2
        exit 1
    fi

    if ! image_id=$(jq -er '.image_id | strings | select(length > 0)' <<<"$ami_metadata") \
        || ! image_name=$(jq -er '.image_name | strings | select(length > 0)' <<<"$ami_metadata") \
        || ! release_version=$(jq -er '.release_version | strings | select(length > 0)' <<<"$ami_metadata"); then
        echo "Malformed SSM AMI metadata for Kubernetes $kubernetes_version" >&2
        exit 1
    fi

    if [[ ! "$image_name" =~ -v([0-9]{8})$ ]]; then
        echo "Unable to derive the EKS AMI release tag from image: $image_name" >&2
        exit 1
    fi
    release_tag="v${BASH_REMATCH[1]}"

    if ! image_state=$(
        "$AWS_BIN" ec2 describe-images \
            --image-ids "$image_id" \
            --region "$REGION" \
            --query 'Images[0].State' \
            --output text
    ); then
        echo "Failed to verify recommended AMI $image_id for Kubernetes $kubernetes_version" >&2
        exit 1
    fi
    if [[ "$image_state" != "available" ]]; then
        echo "Recommended AMI $image_id for Kubernetes $kubernetes_version is not available" >&2
        exit 1
    fi

    release_body_file=$(fetch_release_body "$release_tag")
    kernel_version=$(extract_standard_x86_kernel "$release_body_file" "$kubernetes_version")
    if [[ -z "$kernel_version" ]]; then
        echo "Unable to find the AL2023 x86_64 standard kernel for Kubernetes $kubernetes_version in $release_tag" >&2
        exit 1
    fi
    if [[ ! "$kernel_version" =~ ^([0-9]+)\.([0-9]+)\. ]]; then
        echo "Unexpected kernel version for Kubernetes $kubernetes_version: $kernel_version" >&2
        exit 1
    fi
    kernel_line="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"

    if ! support_status=$(jq -er --arg version "$kubernetes_version" '
        def normalized_status:
            (.versionStatus // .status // "")
            | ascii_upcase
            | gsub("-"; "_");
        .clusterVersions[]
        | select(.clusterVersion == $version)
        | normalized_status
    ' <<<"$cluster_versions_json"); then
        echo "Failed to read support status for Kubernetes $kubernetes_version" >&2
        exit 1
    fi
    if ! end_of_extended_support=$(jq -c --arg version "$kubernetes_version" '
        .clusterVersions[]
        | select(.clusterVersion == $version)
        | .endOfExtendedSupportDate // null
    ' <<<"$cluster_versions_json"); then
        echo "Failed to read support lifecycle for Kubernetes $kubernetes_version" >&2
        exit 1
    fi

    if ! row=$(jq -cn \
        --arg kubernetes_version "$kubernetes_version" \
        --arg support_status "$support_status" \
        --argjson end_of_extended_support "$end_of_extended_support" \
        --arg kernel_line "$kernel_line" \
        --arg kernel_version "$kernel_version" \
        --arg image_id "$image_id" \
        --arg image_name "$image_name" \
        --arg release_version "$release_version" \
        --arg release_tag "$release_tag" \
        '{
            kubernetes_version: $kubernetes_version,
            support_status: $support_status,
            end_of_extended_support: $end_of_extended_support,
            kernel_line: $kernel_line,
            kernel_version: $kernel_version,
            ami_type: "AL2023_x86_64_STANDARD",
            image_id: $image_id,
            image_name: $image_name,
            release_version: $release_version,
            release_tag: $release_tag
        }'); then
        echo "Failed to render matrix entry for Kubernetes $kubernetes_version" >&2
        exit 1
    fi
    printf '%s\n' "$row" >>"$catalog_file"
done < <(jq -r '.[]' <<<"$eligible_versions_json")

if ! catalog_json=$(jq -s 'sort_by(.kubernetes_version | split(".") | map(tonumber))' "$catalog_file"); then
    echo "Failed to render the EKS AL2023 kernel catalog" >&2
    exit 1
fi
if ! matrix_json=$(jq -s '
    group_by(.kernel_line)
    | map(min_by(.kubernetes_version | split(".") | map(tonumber)))
    | sort_by(.kernel_line | split(".") | map(tonumber))
' "$catalog_file"); then
    echo "Failed to render the EKS AL2023 kernel matrix" >&2
    exit 1
fi

if [[ -n "$OUTPUT_FILE" ]]; then
    printf '%s\n' "$matrix_json" >"$OUTPUT_FILE"
fi
if [[ -n "$CATALOG_OUTPUT_FILE" ]]; then
    printf '%s\n' "$catalog_json" >"$CATALOG_OUTPUT_FILE"
fi

case "$OUTPUT_FORMAT" in
    json)
        printf '%s\n' "$matrix_json"
        ;;
    table)
        printf '%-8s %-10s %-18s %-38s %s\n' \
            'KERNEL' 'K8S' 'SUPPORT' 'AMI' 'KERNEL VERSION'
        jq -r '.[] | [
            .kernel_line,
            .kubernetes_version,
            .support_status,
            .image_id,
            .kernel_version
        ] | @tsv' <<<"$matrix_json" \
            | while IFS=$'\t' read -r line version status image kernel; do
                printf '%-8s %-10s %-18s %-38s %s\n' \
                    "$line" "$version" "$status" "$image" "$kernel"
            done
        ;;
esac
