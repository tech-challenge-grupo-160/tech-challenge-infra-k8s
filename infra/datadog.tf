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
  timeout          = 900

  set_sensitive {
    name  = "datadog.apiKey"
    value = var.datadog_api_key
  }

  set {
    name  = "datadog.site"
    value = var.datadog_site
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
    name  = "datadog.logs.containerCollectAll"
    value = "true"
  }

  # Sem hostPort, o dogstatsd do chart so fica acessivel pelo IP do proprio
  # pod do Agent - o app aponta DD_AGENT_HOST para o IP do node (status.hostIP),
  # entao as metricas de negocio (DogStatsD) nunca chegavam ao Agent.
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

  # Sem isso, "agent dogstatsd-stats" so mostra contadores agregados, sem
  # indicar qual metrica/tags o Agent recebeu de fato.
  set {
    name  = "agents.containers.agent.envDict.DD_DOGSTATSD_METRICS_STATS_ENABLE"
    value = "true"
  }

  set {
    name  = "datadog.kubeStateMetricsEnabled"
    value = "true"
  }

  depends_on = [aws_eks_node_group.principal]
}
