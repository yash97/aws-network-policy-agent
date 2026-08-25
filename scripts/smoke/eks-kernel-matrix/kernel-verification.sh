#!/usr/bin/env bash

verify_node_kernel_versions() {
    local expected_kernel="$1"
    shift

    if [[ $# -eq 0 ]]; then
        echo "No worker-node kernel versions were discovered" >&2
        return 1
    fi

    local observed_kernel normalized_kernel
    for observed_kernel in "$@"; do
        normalized_kernel="${observed_kernel%.x86_64}"
        if [[ "$normalized_kernel" != "$expected_kernel" ]]; then
            echo "Expected kernel $expected_kernel on every node; observed $observed_kernel" >&2
            return 1
        fi
    done
}
