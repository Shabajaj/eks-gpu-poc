provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

# NVIDIA Device Plugin — runs as a DaemonSet on every GPU node,
# advertises nvidia.com/gpu as a schedulable resource to the
# Kubernetes scheduler. Without this, the GPU is invisible to K8s
# even though the node has the hardware and driver installed.
resource "helm_release" "nvidia_device_plugin" {
  name       = "nvidia-device-plugin"
  repository = "https://nvidia.github.io/k8s-device-plugin"
  chart      = "nvidia-device-plugin"
  version    = "0.17.0"
  namespace  = "kube-system"

  # Tolerate the taint we set on the GPU node group so the
  # device plugin itself can actually run there
  set {
    name  = "tolerations[0].key"
    value = "nvidia.com/gpu"
    type  = "string"
  }
  set {
    name  = "tolerations[0].operator"
    value = "Equal"
    type  = "string"
  }
  set {
    name  = "tolerations[0].value"
    value = "true"
    type  = "string"
  }
  set {
    name  = "tolerations[0].effect"
    value = "NoSchedule"
    type  = "string"
  }

  depends_on = [module.eks]
}
