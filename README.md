# EKS GPU Node Group — Terraform POC

## What this is
A validated Terraform configuration that provisions:
- A VPC (public/private subnets across 2 AZs, NAT gateway)
- An EKS cluster with two managed node groups:
  - `default` — general workloads, on-demand `m5.large`
  - `gpu` — GPU workloads, Spot `g4dn.xlarge`, tainted so only GPU-tolerant pods land there
- The NVIDIA Device Plugin, deployed via Terraform's `helm_release` resource so the
  entire stack — infra AND the Kubernetes addon — is IaC-managed, not manual `kubectl apply`

This POC was intentionally run through `plan` only, not `apply`, to avoid real GPU
spend on a personal project. In production, `apply` would only run after this
exact kind of plan review — a manual approval gate between `plan` and `apply`,
which prevents unreviewed infrastructure changes (including destructive ones)
from applying automatically.

## Steps to run (plan-only, $0 cost)

```bash
# 1. Install Terraform (if not already installed)
brew install terraform          # or appropriate for your OS

# 2. Configure AWS credentials
aws configure                   # needs an AWS account, but no resources are created

# 3. Initialize — downloads the VPC and EKS provider modules
terraform init

# 4. Validate syntax and internal consistency
terraform validate

# 5. Generate and review the plan — THIS is the artifact to show in interview
terraform plan -out=tfplan

# 6. (Optional) Human-readable plan output for screenshots/walkthrough
terraform show tfplan
```

`terraform plan` will show something like:
```
Plan: 47 to add, 0 to change, 0 to destroy.
```
This is what proves the configuration is real and valid — Terraform is talking to
AWS, validating your VPC CIDR ranges, checking IAM permissions, and confirming the
EKS/node group configuration would actually succeed, without creating anything.

## Steps to run for real (~$1-3, ~30-45 min, optional stretch goal)

```bash
# 7. Apply — this is where real billing starts
terraform apply tfplan

# 8. Configure kubectl (command is in the Terraform output)
aws eks update-kubeconfig --region us-east-1 --name gpu-poc-cluster

# 9. Confirm the GPU node registered and is labeled correctly
kubectl get nodes -L nvidia.com/gpu.present

# 10. Confirm the device plugin DaemonSet is running
kubectl get pods -n kube-system -l app=nvidia-device-plugin

# 11. Run the smoke test pod
kubectl apply -f gpu-test-pod.yaml
kubectl logs gpu-smoke-test
# Expected: nvidia-smi output showing the Tesla T4 GPU on the g4dn.xlarge instance

# 12. IMPORTANT — tear down immediately to stop billing
kubectl delete -f gpu-test-pod.yaml
terraform destroy
```

To avoid an accidental long-running GPU node, `gpu_desired_size` defaults to `0`
in `variables.tf`. Flip it to `1` only right before the demo:
```bash
terraform apply -var="gpu_desired_size=1"
# ... do the demo ...
terraform apply -var="gpu_desired_size=0"   # scale back down without a full destroy
```

## Interview talking points tied to this POC

- **Scheduler/taints**: "The GPU node group has a taint so only pods that explicitly
  tolerate `nvidia.com/gpu` get scheduled there — prevents ordinary workloads from
  landing on an expensive GPU node by accident."
- **Device plugin**: "Without the NVIDIA device plugin DaemonSet, Kubernetes has no
  idea the GPU exists — it would treat this node like any plain compute node. The
  plugin advertises `nvidia.com/gpu` as a schedulable resource."
- **Cost discipline**: "I used Spot capacity for the GPU node group and kept
  `desired_size` at 0 by default — this mirrors the kind of cost-optimization
  thinking that matters at GPU cluster scale."
- **IaC discipline**: "Even the Helm-deployed device plugin is provisioned through
  Terraform, not a manual `helm install` — so the whole stack has one source of
  truth and one review process."
- **Plan gating**: "I intentionally only ran `plan`, not `apply`, for this personal
  project — in a real pipeline this would be the exact checkpoint where a human
  reviews the plan output before approving `apply`, which matters more for
  infrastructure than app deploys since some changes aren't cleanly reversible."
- **GitOps note**: "The infra (VPC, cluster, node groups, device plugin) is
  Terraform-managed. The actual workload — the test pod — I applied directly here
  for the demo, but in a real setup that would go through GitOps via ArgoCD rather
  than manual kubectl."

## Known limitations (be upfront if asked)
- Single NAT gateway (`single_nat_gateway = true`) — cost-saving for a POC;
  production would use one NAT per AZ for high availability
- `endpoint_public_access = true` — fine for a POC, would be restricted/private
  in a real production cluster
- No multi-node distributed training setup (no EFA, no PyTorchJob/Kubeflow) —
  intentionally out of scope to keep this POC focused and explainable
