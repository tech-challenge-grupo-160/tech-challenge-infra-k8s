resource "aws_secretsmanager_secret" "datadog_api_key" {
  count = var.datadog_enabled ? 1 : 0

  name                    = "${var.project}/${var.ambiente}/datadog-api-key"
  description             = "Chave da API Datadog para o Agent e as Lambdas."
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "datadog_api_key" {
  count = var.datadog_enabled ? 1 : 0

  secret_id     = aws_secretsmanager_secret.datadog_api_key[0].id
  secret_string = var.datadog_api_key
}

resource "helm_release" "datadog_agent" {
  count = var.criar_cluster && var.datadog_enabled ? 1 : 0

  name             = "datadog"
  namespace        = "datadog"
  create_namespace = true
  repository       = "https://helm.datadoghq.com"
  chart            = "datadog"

  set_sensitive {
    name  = "datadog.apiKey"
    value = var.datadog_api_key
  }

  set {
    name  = "datadog.site"
    value = "datadoghq.com"
  }

  set {
    name  = "datadog.clusterName"
    value = "${var.project}-${var.ambiente}"
  }

  set {
    name  = "datadog.apm.portEnabled"
    value = "true"
  }

  set {
    name  = "datadog.logs.enabled"
    value = "true"
  }

  set {
    name  = "datadog.dogstatsd.port"
    value = "8125"
  }

  set {
    name  = "datadog.dogstatsd.useHostPort"
    value = "true"
  }

  set {
    name  = "datadog.dogstatsd.nonLocalTraffic"
    value = "true"
  }

  # Sem isso, "agent dogstatsd-stats" nao mostra por qual metrica/tags o
  # Agent esta recebendo trafego - so da pra ver contadores agregados. Nao
  # existe um valor datadog.dogstatsd.* dedicado no chart para essa flag; ela
  # e so um env var repassado ao container do agent.
  set {
    name  = "agents.containers.agent.envDict.DD_DOGSTATSD_METRICS_STATS_ENABLE"
    value = "true"
  }

  set {
    name  = "datadog.logs.containerCollectAll"
    value = "true"
  }

  set {
    name  = "datadog.kubeStateMetricsEnabled"
    value = "true"
  }

  depends_on = [aws_eks_node_group.principal]
}
