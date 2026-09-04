output "cluster_name" {
  description = "Nome do cluster kind criado"
  value       = kind_cluster.oficina_mecanica.name
}

output "cluster_endpoint" {
  description = "Endpoint da API do Kubernetes usado pelo kubectl e provider kubernetes"
  value       = kind_cluster.oficina_mecanica.endpoint
}

output "kubeconfig_path" {
  description = "Caminho do kubeconfig gerado pelo kind"
  value       = kind_cluster.oficina_mecanica.kubeconfig_path
}

output "namespace" {
  description = "Namespace criado para a aplicacao"
  value       = kubernetes_namespace.oficina_mecanica.metadata[0].name
}

output "next_steps" {
  description = "Comandos para verificar o cluster apos o apply"
  value       = <<-EOT

    Cluster '${kind_cluster.oficina_mecanica.name}' pronto.

    Verifique os nos:
      kubectl get nodes

    Aplique os manifestos da aplicacao:
      kubectl apply -k k8s/

    Verifique os pods:
      kubectl get pods -n ${var.namespace}

    Acesse a API via NodePort:
      http://localhost:${var.api_host_port}

    Para destruir o cluster quando nao precisar mais:
      terraform destroy
  EOT
}
