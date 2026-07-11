terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ------------------------------------------------------------------
# VPC — using the official AWS VPC module (industry standard, not
# hand-rolled, keeps this consistent with how real teams provision it)
# ------------------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true # cost-saving for a POC; production would use one per AZ

  # Required tags so the EKS/ELB controllers can discover these subnets
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = var.tags
}

# ------------------------------------------------------------------
# EKS Cluster — official terraform-aws-modules/eks module
# ------------------------------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  endpoint_public_access = true # POC convenience; would be false/restricted in prod

  enable_cluster_creator_admin_permissions = true

  addons = {
    coredns                = {}
    kube-proxy              = {}
    vpc-cni                 = { before_compute = true }
    eks-pod-identity-agent  = { before_compute = true }
  }

  eks_managed_node_groups = {
    # ---- Default node group: core addons, no GPU needed ----
    # t3.micro was the original choice (cheapest possible, fine for
    # "prove the infra provisions" purposes) but hits a hard 4-pod-per-node
    # ceiling from AWS's ENI-based pod density limit for that instance
    # size — before any workload pods are even scheduled, system
    # daemonsets (aws-node, kube-proxy, coredns, eks-pod-identity-agent)
    # already consume all 4 slots. t3.small (11 pods/node) was enough for
    # Kaniko builds and training Jobs, but Istio + Knative Serving + KServe
    # (installed for real weighted canary rollout support) bring a control
    # plane easily 10+ pods heavier, with correspondingly bigger memory
    # requests (istiod alone typically wants several hundred MB).
    #
    # t3.medium was tried first and rejected outright by AWS: this account
    # is restricted to Free Tier-eligible instance types only
    # (InvalidParameterCombination error on launch — a hard account-level
    # policy, not a quota/capacity issue). m7i-flex.large IS on the Free
    # Tier-eligible list (confirmed via `aws ec2 describe-instance-types
    # --filters Name=free-tier-eligible,Values=true`) and has the same 2
    # vCPUs as t3.small but 4x the memory (8GB vs 2GB) — the best fit
    # available for Istio's heavier footprint under this constraint.
    default = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["m7i-flex.large"]
      capacity_type  = "ON_DEMAND"

      min_size     = 2
      max_size     = 2
      desired_size = 2
    }

    # ---- GPU node group: cheapest real GPU instance, Spot for cost ----
    gpu = {
      ami_type       = "AL2023_x86_64_NVIDIA" # pre-baked with NVIDIA driver + container toolkit
      instance_types = ["g4dn.xlarge"]        # cheapest GPU instance (~$0.526/hr on-demand, less on Spot)
      capacity_type  = "SPOT"

      min_size     = 0
      max_size     = 1
      desired_size = var.gpu_desired_size # set to 0 by default — flip to 1 only when actively demoing

      labels = {
        "nvidia.com/gpu.present" = "true"
      }

      # Taint ensures only GPU-tolerant pods get scheduled here —
      # prevents ordinary workloads from wasting the expensive GPU node
      taints = {
        gpu = {
          key    = "nvidia.com/gpu"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }

  tags = var.tags
}
