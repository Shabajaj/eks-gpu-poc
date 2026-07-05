variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "gpu-poc-cluster"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS control plane"
  type        = string
  default     = "1.33"
}

variable "gpu_desired_size" {
  description = "Desired size of the GPU node group. Keep at 0 to avoid GPU billing; set to 1 only when actively demoing."
  type        = number
  default     = 0
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    Project     = "eks-gpu-poc"
    Environment = "poc"
    ManagedBy   = "terraform"
  }
}
