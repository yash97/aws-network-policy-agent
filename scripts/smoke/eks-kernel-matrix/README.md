# EKS AL2023 kernel-matrix smoke test

This smoke test discovers the kernel lines exposed by the latest EKS-optimized
AL2023 x86_64 standard AMIs for currently supported Amazon EKS Kubernetes
versions. It selects the lowest supported Kubernetes version for each unique
kernel line.

The script is read-only. It does not create clusters, node groups, or other AWS
resources.

## Selection policy

A candidate must meet all of these conditions:

1. Its Kubernetes version is returned by `eks:DescribeClusterVersions` with an
   allowed support status.
2. It is the SSM-recommended AL2023 x86_64 standard AMI for that Kubernetes
   version.
3. The AMI is currently available in the selected Region.
4. Its kernel is listed for `AL2023_x86_64_STANDARD` in the corresponding
   official `awslabs/amazon-eks-ami` GitHub release.

Candidates are grouped by the kernel major/minor line, such as `6.12`. The
first Kubernetes version in ascending order is selected for each line. Full
kernel package versions are retained in the output for traceability.

Bottlerocket, AL2, custom AMIs, historical AMIs, and unsupported Kubernetes
versions cannot introduce kernel lines into this matrix.

## Requirements

- AWS CLI v2 with read access to EKS, SSM public parameters, and EC2 images
- `curl`
- `jq`
- `awk`

Use a ReadOnly or otherwise least-privilege AWS profile.

## Run

```bash
AWS_PROFILE=<readonly-profile> \
AWS_REGION=us-west-2 \
./scripts/smoke/eks-kernel-matrix/run.sh
```

The default includes both `STANDARD_SUPPORT` and `EXTENDED_SUPPORT` versions.
These are the only accepted support statuses; unsupported Kubernetes versions
cannot be enabled through configuration. To restrict the matrix to standard
support:

```bash
EKS_SUPPORT_STATUSES=STANDARD_SUPPORT \
AWS_PROFILE=<readonly-profile> \
./scripts/smoke/eks-kernel-matrix/run.sh
```

Use JSON output for automation:

```bash
OUTPUT_FORMAT=json \
OUTPUT_FILE=/tmp/eks-kernel-matrix.json \
CATALOG_OUTPUT_FILE=/tmp/eks-kernel-catalog.json \
AWS_PROFILE=<readonly-profile> \
./scripts/smoke/eks-kernel-matrix/run.sh
```

`OUTPUT_FILE` contains the selected unique-kernel matrix. The optional
`CATALOG_OUTPUT_FILE` contains every eligible Kubernetes/AMI/kernel candidate
considered by the script.

If `GITHUB_TOKEN` is set, the script uses the authenticated GitHub API. Without
a token, it reads the public GitHub release page directly to avoid anonymous API
rate limits.

## Offline validation

The offline test uses mocked AWS and GitHub responses and does not require AWS
credentials:

```bash
./scripts/smoke/eks-kernel-matrix/test.sh
```

It verifies:

- unsupported Kubernetes versions are excluded;
- extended-support versions can be included or excluded by policy;
- the parser selects the AL2023 x86_64 standard column rather than an ARM or
  accelerated-image kernel;
- each kernel line selects the first eligible Kubernetes version;
- every worker node must report the exact expected kernel package; and
- cluster names stay stable across GitHub rerun attempts so cleanup targets the
  original cluster.

The live script intentionally fails if the official release-note structure no
longer exposes the expected kernel package data. This prevents silently
selecting an incorrect kernel.

## Nightly GitHub workflow

`.github/workflows/nightly-kernel-cyclonus.yaml` runs daily at 07:00 UTC and
can also be started manually. It builds the Network Policy Agent image from the
repository's default branch, consumes this script's selected matrix, and runs
one Cyclonus job for every kernel candidate and IP family (`IPv4` and `IPv6`).
Each job pins its managed node group to the selected AMI, verifies the runtime
AMI and kernel line, installs the newly built node-agent image, and runs the
same Cyclonus and integration suites used by the PR bot. Separate cleanup jobs
retry cluster deletion even when a test leg fails or times out.
