#!/bin/bash

# Runs the kernel-sensitive test suites against an existing cluster. Both
# suites run identically on IPv4 and IPv6 clusters, so every kernel line in
# the nightly matrix gets the same coverage:
#   policy.test - network policy enforcement through the agent's TC programs
#   strict.test - strict enforcement mode (mutates aws-node, so it runs last)
#
# Parameters:
# CLUSTER_NAME: name of the cluster
# KUBECONFIG: path to the cluster kubeconfig file
# REGION: defaults to us-west-2
# IP_FAMILY: defaults to IPv4
# TEST_IMAGE_REGISTRY: defaults to registry.k8s.io

set -euoE pipefail
DIR=$(cd "$(dirname "$0")"; pwd)
GINKGO_TEST_BUILD_DIR="$DIR/../test/build"

: "${IP_FAMILY:="IPv4"}"
: "${REGION:="us-west-2"}"
: "${TEST_IMAGE_REGISTRY:="registry.k8s.io"}"
: "${KUBE_CONFIG_PATH:=$KUBECONFIG}"

TEST_FAILED="false"

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

echo "Nodes for cluster: $CLUSTER_NAME"
kubectl get nodes -owide

echo "Making ginkgo test binaries"
(cd $DIR/.. && make build-test-binaries)

run_ginkgo_suite policy.test 15m

echo "Enable network policy strict mode"
kubectl set env daemonset aws-node -n kube-system -c aws-node NETWORK_POLICY_ENFORCING_MODE=strict
kubectl rollout status ds/aws-node -n kube-system --timeout=300s

run_ginkgo_suite strict.test 15m

if [[ $TEST_FAILED == "true" ]]; then
    echo "Test run failed"
    exit 1
fi
