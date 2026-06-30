output "cluster_name" {
  description = "Nome do cluster kind criado"
  value       = kind_cluster.oficina_mecanica.name
}

output "cluster_endpoint" {
  description = "Endpoint da API do Kubernetes (usado pelo kubectl e pelo provider kubernetes)"
  value       = kind_cluster.oficina_mecanica.endpoint
}

output "kubeconfig_path" {
  description = "Caminho do kubeconfig gerado pelo kind (atualizado automaticamente pelo Terraform)"
  value       = kind_cluster.oficina_mecanica.kubeconfig_path
}

output "namespace" {
  description = "Namespace criado para a aplicação"
  value       = kubernetes_namespace.oficina_mecanica.metadata[0].name
}

output "next_steps" {
  description = "Comandos para verificar o cluster após o apply"
  value       = <<-EOT

    ✅ Cluster '${kind_cluster.oficina_mecanica.name}' pronto!

    Verifique os nós:
      kubectl get nodes

    Aplique os manifestos da aplicação:
      kubectl apply -k k8s/

    Verifique os pods:
      kubectl get pods -n oficina-mecanica

    Acesse a API (via NodePort):
      http://localhost:${var.api_host_port}

    Para destruir o cluster quando não precisar mais:
      terraform destroy
  EOT
}
