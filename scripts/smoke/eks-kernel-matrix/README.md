# Nightly EKS kernel tests

`run.sh` discovers all Kubernetes versions in standard or extended EKS support,
reads each latest AL2023 x86_64 standard AMI from public SSM parameters, and
selects the lowest Kubernetes version for every unique kernel line.

```bash
AWS_REGION=us-west-2 ./scripts/smoke/eks-kernel-matrix/run.sh
```

The script is read-only and prints a JSON matrix containing the Kubernetes
version, AMI ID, kernel line, and exact kernel package. `test.sh` validates the
discovery and deduplication logic without AWS credentials.

`.github/workflows/nightly-kernel-cyclonus.yaml` runs nightly at 07:00 UTC and
through manual dispatch. It builds the default-branch image, creates one cluster
for every selected kernel and IP family, verifies the AMI and exact kernel on
all nodes, runs the existing Cyclonus suites, and deletes the clusters in
separate retrying cleanup jobs.
