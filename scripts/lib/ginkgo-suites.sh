#!/usr/bin/env bash

# Shared helpers for running the prebuilt integration suite binaries
# (test/build/*.test) against an existing cluster.
#
# Callers must set before use:
#   GINKGO_TEST_BUILD_DIR: directory containing the suite binaries
#   CLUSTER_NAME, KUBE_CONFIG_PATH, TEST_IMAGE_REGISTRY, IP_FAMILY
#   TEST_FAILED: initialized to "false"; set to "true" when any suite fails

# Runs a prebuilt ginkgo suite binary against the cluster. Records any failure
# in TEST_FAILED (instead of aborting) so the remaining suites still run.
run_ginkgo_suite() {
    local suite_binary="$1"
    local timeout="${2:-15m}"
    echo "Running ${suite_binary} (timeout ${timeout})"
    CGO_ENABLED=0 ginkgo -v -timeout "$timeout" --no-color --fail-on-pending \
        "$GINKGO_TEST_BUILD_DIR/$suite_binary" -- \
        --cluster-kubeconfig="$KUBE_CONFIG_PATH" \
        --cluster-name="$CLUSTER_NAME" \
        --test-image-registry="$TEST_IMAGE_REGISTRY" \
        --ip-family="$IP_FAMILY" || TEST_FAILED="true"
}

# Switches the aws-node daemonset to strict network policy enforcement and
# waits for the rollout. Mutates cluster state, so run the strict suite last.
enable_strict_mode() {
    echo "Enable network policy strict mode"
    kubectl set env daemonset aws-node -n kube-system -c aws-node NETWORK_POLICY_ENFORCING_MODE=strict

    echo "Check aws-node daemonset status"
    kubectl rollout status ds/aws-node -n kube-system --timeout=300s
}
