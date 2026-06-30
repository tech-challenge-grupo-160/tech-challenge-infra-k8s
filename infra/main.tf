provider "kind" {}

resource "kind_cluster" "oficina_mecanica" {
  name            = var.cluster_name
  node_image      = "kindest/node:${var.kubernetes_version}"
  wait_for_ready  = true 

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    dynamic "node" {
      for_each = range(var.control_plane_count)
      content {
        role = "control-plane"
        kubeadm_config_patches = [
          "kind: InitConfiguration\nnodeRegistration:\n  kubeletExtraArgs:\n    node-labels: \"ingress-ready=true\"\n"
        ]

        extra_port_mappings {
          container_port = 80
          host_port      = var.ingress_http_port
          protocol       = "TCP"
        }
        extra_port_mappings {
          container_port = 443
          host_port      = var.ingress_https_port
          protocol       = "TCP"
        }

        extra_port_mappings {
          container_port = 30080
          host_port      = var.api_host_port
          protocol       = "TCP"
        }
      }
    }

    dynamic "node" {
      for_each = range(var.worker_count)
      content {
        role = "worker"
      }
    }
  }
}

provider "kubernetes" {
  # Usa o kubeconfig gerado pelo kind diretamente.
  # Evita base64decode em campos que chegam vazios durante
  # a criação do cluster, causando "Error in function call".
  config_path = kind_cluster.oficina_mecanica.kubeconfig_path
}

resource "kubernetes_namespace" "oficina_mecanica" {
  metadata {
    name = "oficina-mecanica"

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "oficina-mecanica"
    }
  }

  depends_on = [kind_cluster.oficina_mecanica]
}


# =========================================================
# Metrics Server
# Necessário para o HPA conseguir ler CPU/memória dos pods.
# Instalado via kubectl após o cluster estar pronto, com o
# patch --kubelet-insecure-tls exigido pelo kind.
# =========================================================
resource "null_resource" "metrics_server" {
  triggers = {
    cluster_name = kind_cluster.oficina_mecanica.name
  }

  provisioner "local-exec" {
    command = <<-CMD
      kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
      kubectl patch deployment metrics-server -n kube-system --type=json -p="[{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/args/-\",\"value\":\"--kubelet-insecure-tls\"}]"
    CMD

    environment = {
      KUBECONFIG = kind_cluster.oficina_mecanica.kubeconfig_path
    }
  }

  depends_on = [
    kind_cluster.oficina_mecanica,
    kubernetes_namespace.oficina_mecanica
  ]
}

# =========================================================
# Secrets da aplicação gerenciados diretamente pelo
# provider kubernetes — sem null_resource nem shell,
# funciona igual em Windows, Linux e Mac.
# =========================================================
resource "kubernetes_secret" "postgres_secret" {
  metadata {
    name      = "postgres-secret"
    namespace = kubernetes_namespace.oficina_mecanica.metadata[0].name
  }

  data = {
    POSTGRES_USER     = var.postgres_user
    POSTGRES_PASSWORD = var.postgres_password
  }

  depends_on = [kubernetes_namespace.oficina_mecanica]
}

resource "kubernetes_secret" "api_secret" {
  metadata {
    name      = "api-secret"
    namespace = kubernetes_namespace.oficina_mecanica.metadata[0].name
  }

  data = {
    "ConnectionStrings__DefaultConnection" = "Host=postgres;Database=${var.postgres_db};Username=${var.postgres_user};Password=${var.postgres_password}"
    "Jwt__SecretKey"                       = var.jwt_secret_key
  }

  depends_on = [kubernetes_namespace.oficina_mecanica]
}

resource "null_resource" "k8s_manifests" {
  triggers = {
    cluster_name = kind_cluster.oficina_mecanica.name
  }

  provisioner "local-exec" {
    # Caminho relativo a partir da pasta infra/ onde o Terraform roda.
    # ../k8s aponta para a pasta k8s/ na raiz do projeto.
    command = "kubectl apply -k ../k8s"

    environment = {
      KUBECONFIG = kind_cluster.oficina_mecanica.kubeconfig_path
    }
  }

  depends_on = [
    null_resource.metrics_server,
    kubernetes_secret.postgres_secret,
    kubernetes_secret.api_secret
  ]
}
