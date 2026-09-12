locals {
  datadog_uptime_message = join(" ", compact([
    "Uptime indisponivel para ${var.ambiente}.",
    "Investigar API Gateway, API e Lambda.",
    join(" ", var.datadog_notification_targets)
  ]))
}

resource "datadog_synthetics_test" "api_uptime" {
  count = var.datadog_synthetics_enabled ? 1 : 0

  name      = "${var.project}-${var.ambiente}-api-uptime"
  type      = "api"
  subtype   = "http"
  status    = "live"
  locations = var.datadog_synthetic_locations
  message   = local.datadog_uptime_message
  tags      = ["service:${var.project}", "env:${var.ambiente}", "component:api", "check:uptime"]

  request_definition {
    method = "GET"
    url    = "${aws_apigatewayv2_api.principal.api_endpoint}/${var.ambiente}/health/live"
  }

  assertion {
    type     = "statusCode"
    operator = "is"
    target   = "200"
  }

  options_list {
    tick_every = 300

    retry {
      count    = 2
      interval = 300
    }

    monitor_options {
      renotify_interval = 60
    }
  }
}

resource "datadog_synthetics_test" "lambda_uptime" {
  count = var.datadog_synthetics_enabled ? 1 : 0

  name      = "${var.project}-${var.ambiente}-lambda-uptime"
  type      = "api"
  subtype   = "http"
  status    = "live"
  locations = var.datadog_synthetic_locations
  message   = local.datadog_uptime_message
  tags      = ["service:${var.project}", "env:${var.ambiente}", "component:lambda", "check:uptime"]

  request_definition {
    method = "POST"
    url    = "${aws_apigatewayv2_api.principal.api_endpoint}/${var.ambiente}/auth"
    body   = "{}"
  }

  # Payload vazio e controlado valida disponibilidade sem expor credenciais.
  assertion {
    type     = "statusCode"
    operator = "is"
    target   = "400"
  }

  options_list {
    tick_every = 300

    retry {
      count    = 2
      interval = 300
    }

    monitor_options {
      renotify_interval = 60
    }
  }
}

resource "datadog_dashboard_json" "uptime" {
  count = var.datadog_synthetics_enabled ? 1 : 0

  dashboard = jsonencode({
    title        = "${var.project} - Uptime - ${var.ambiente}"
    description  = "Historico dos monitores sinteticos da API e da Lambda."
    layout_type  = "ordered"
    is_read_only = false
    widgets = [
      {
        definition = {
          type      = "alert_graph"
          title     = "Status historico da API"
          alert_id  = tostring(datadog_synthetics_test.api_uptime[0].monitor_id)
          viz_type  = "timeseries"
          live_span = "1h"
        }
      },
      {
        definition = {
          type      = "alert_graph"
          title     = "Status historico da Lambda"
          alert_id  = tostring(datadog_synthetics_test.lambda_uptime[0].monitor_id)
          viz_type  = "timeseries"
          live_span = "1h"
        }
      },
      {
        definition = {
          type  = "timeseries"
          title = "Latencia dos testes sinteticos"
          requests = [
            {
              q            = "avg:synthetics.http.response.time{service:${var.project},env:${var.ambiente}} by {component}"
              display_type = "line"
              style        = { line_type = "solid", line_width = "normal" }
            }
          ]
        }
      },

      {
        definition = {
          type  = "query_value"
          title = "Ordens criadas"
          requests = [
            {
              q = "sum:oficina_mecanica.orders.created{service:${var.project},env:${var.ambiente}}.as_count()"
            }
          ]
          autoscale = true
          precision = 0
        }
      },
      {
        definition = {
          type  = "timeseries"
          title = "Falhas de negocio na criacao de ordens"
          requests = [
            {
              q            = "sum:oficina_mecanica.orders.creation_failed{service:${var.project},env:${var.ambiente}} by {reason}.as_count()"
              display_type = "bars"
              style        = { line_type = "solid", line_width = "normal" }
            }
          ]
        }
        }, {
        definition = {
          type  = "query_value"
          title = "Execucoes sinteticas"
          requests = [
            {
              q = "sum:synthetics.test_runs{service:${var.project},env:${var.ambiente}}"
            }
          ]
          autoscale = true
          precision = 0
        }
      }
    ]
  })
}