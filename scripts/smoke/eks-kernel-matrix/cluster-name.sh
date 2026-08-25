#!/usr/bin/env bash

nightly_kernel_cluster_name() {
    local kernel_line="$1"
    local ip_family="$2"
    local run_id="$3"
    local kernel_slug="${kernel_line//./-}"
    local ip_slug

    ip_slug=$(tr '[:upper:]' '[:lower:]' <<<"$ip_family")
    printf 'npa-nightly-k%s-%s-%s\n' "$kernel_slug" "$ip_slug" "$run_id"
}
