# API Gateway HTTP API (issue #42 / F3-08).
#
# Porta de entrada da aplicacao. A escolha do HTTP API sobre o REST API e a
# justificativa estao na RFC-0002; o mapa de rotas publicas e protegidas, na
# matriz de autorizacao (docs/MATRIZ_AUTORIZACAO.md do repositorio principal).
#
# O authorizer NAO entra aqui - e a issue #43 (F3-09). Todas as rotas nascem
# com authorization_type NONE e a issue seguinte troca as protegidas.

locals {
  # A Lambda de autenticacao NAO e criada por este Terraform: o pipeline do
  # repositorio tech-challenge-lambda-auth publica com `dotnet lambda
  # deploy-function`. Gerenciar aqui faria os dois disputarem a mesma funcao.
  #
  # O ARN e montado em vez de lido com `data aws_lambda_function` de proposito:
  # a funcao de um ambiente so existe depois do primeiro deploy daquele
  # ambiente, e um data source apontando para funcao inexistente derruba o
  # `terraform plan` - que bloqueia PR neste repositorio. Montar o ARN mantem o
  # plan honesto nos tres ambientes; o apply so roda em hom e prod, onde a
  # funcao existe.
  lambda_auth_nome = coalesce(
    var.lambda_auth_nome,
    "${var.project}-auth-${var.ambiente}"
  )

  lambda_auth_arn = join("", [
    "arn:aws:lambda:",
    var.region,
    ":",
    data.aws_caller_identity.atual.account_id,
    ":function:",
    local.lambda_auth_nome
  ])

  # As rotas da aplicacao existem quando existe cluster: o ALB interno da issue
  # #64 nasce junto com ele, em alb.tf, e e para o listener dele que a
  # integracao aponta.
  #
  # Ate 30/08 isto dependia de var.alb_listener_arn, preenchida a mao depois que
  # alguem criasse o balanceador por fora. Com o ALB no mesmo Terraform, a
  # referencia e direta e o passo manual desaparece.
  integrar_cluster = var.criar_cluster
}

# ------------------------------------------------------------------- o gateway

resource "aws_apigatewayv2_api" "principal" {
  name          = "${var.project}-${var.ambiente}"
  description   = "Porta de entrada da oficina mecanica: autenticacao por CPF e API de gestao."
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
    allow_headers = ["Authorization", "Content-Type"]
    max_age       = 300
  }
}

# ------------------------------------------------------------ logs de acesso

resource "aws_cloudwatch_log_group" "gateway" {
  name              = "/aws/apigateway/${var.project}-${var.ambiente}"
  retention_in_days = var.gateway_log_retention_days
}

# ------------------------------------------------------------------- estagio

resource "aws_apigatewayv2_stage" "principal" {
  api_id      = aws_apigatewayv2_api.principal.id
  name        = var.ambiente
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.gateway.arn

    # Formato enxuto e suficiente para auditoria. O `authorizerError` entra
    # aqui de proposito: quando a issue #43 ligar o authorizer, ele e o campo
    # que diz por que uma requisicao foi recusada na borda.
    format = jsonencode({
      requestId       = "$context.requestId"
      ip              = "$context.identity.sourceIp"
      requestTime     = "$context.requestTime"
      httpMethod      = "$context.httpMethod"
      routeKey        = "$context.routeKey"
      status          = "$context.status"
      protocol        = "$context.protocol"
      responseLength  = "$context.responseLength"
      integrationTime = "$context.integrationLatency"
      authorizerError = "$context.authorizer.error"
    })
  }

  default_route_settings {
    throttling_rate_limit  = var.gateway_rate_limit
    throttling_burst_limit = var.gateway_burst_limit
  }
}

# --------------------------------------------------- rota de autenticacao

resource "aws_apigatewayv2_integration" "auth_lambda" {
  api_id           = aws_apigatewayv2_api.principal.id
  integration_type = "AWS_PROXY"
  integration_uri  = local.lambda_auth_arn
  # 1.0, nao 2.0. O handler recebe APIGatewayProxyRequest, que e o formato 1.0.
  # No evento 2.0 o metodo vive em requestContext.http.method e o campo
  # httpMethod nem existe, entao a desserializacao deixa HttpMethod nulo e a
  # funcao devolve 405 para toda requisicao - inclusive POST.
  #
  # Diagnosticado em 2026-08-27 no primeiro apply de dev: o gateway entregava
  # o evento, a Lambda respondia "Metodo nao permitido: ." com o metodo vazio.
  #
  # 2.0 e o padrao do HTTP API e seria a escolha natural para codigo novo.
  # Migrar exigiria trocar o handler para APIGatewayHttpApiV2ProxyRequest e
  # APIGatewayHttpApiV2ProxyResponse no repositorio da Lambda - alinhar a
  # integracao ao codigo existente resolve com uma linha e sem risco.
  payload_format_version = "1.0"
  timeout_milliseconds   = 29000
}

resource "aws_apigatewayv2_route" "auth" {
  api_id    = aws_apigatewayv2_api.principal.id
  route_key = "POST /auth"
  target    = "integrations/${aws_apigatewayv2_integration.auth_lambda.id}"

  # Publica por definicao: e a rota que emite o token. Ver a matriz de
  # autorizacao. Continua NONE depois da issue #43.
  authorization_type = "NONE"
}

resource "aws_lambda_permission" "gateway_invoca_auth" {
  statement_id  = "AllowInvokeFromApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = local.lambda_auth_nome
  principal     = "apigateway.amazonaws.com"

  # Restringe a invocacao a este gateway. Sem o source_arn qualquer API
  # Gateway da conta poderia chamar a funcao.
  source_arn = "${aws_apigatewayv2_api.principal.execution_arn}/*/*"
}

# ------------------------------------------- rotas da aplicacao no cluster

resource "aws_apigatewayv2_vpc_link" "cluster" {
  count = local.integrar_cluster ? 1 : 0

  name = "${var.project}-${var.ambiente}-cluster"

  # Subnets privadas, nao publicas: o balanceador e interno e vive nelas. As
  # ENIs do link compartilham o sg_alb com o ALB, e a regra auto-referenciada
  # em alb.tf e o que permite uma alcancar a outra.
  subnet_ids         = aws_subnet.privada[*].id
  security_group_ids = [aws_security_group.alb.id]
}

resource "aws_apigatewayv2_integration" "api_cluster" {
  count = local.integrar_cluster ? 1 : 0

  api_id             = aws_apigatewayv2_api.principal.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = aws_lb_listener.api[0].arn
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.cluster[0].id

  # Sem isto o gateway repassa o nome do estagio no caminho: uma chamada a
  # /dev/health/live chega na API como /dev/health/live, e ela devolve 404 -
  # nao conhece esse prefixo. Vale para todas as rotas do cluster.
  #
  # `$request.path` e o caminho JA sem o estagio, entao um unico mapeamento na
  # integracao resolve as tres rotas de uma vez. A alternativa seria usar o
  # estagio `$default`, que nao tem prefixo - descartada porque a issue #42 pede
  # estagios de homologacao e producao configurados.
  #
  # Diagnosticado em 2026-08-30 no primeiro apply: /health/live respondia 200
  # direto no ALB e 404 pelo gateway.
  request_parameters = {
    "overwrite:path" = "$request.path"
  }
}

# Login administrativo do seed: publico, como o /auth. Precisa de rota
# propria porque o {proxy+} abaixo recebe o authorizer na issue #43.
resource "aws_apigatewayv2_route" "login_api" {
  count = local.integrar_cluster ? 1 : 0

  api_id             = aws_apigatewayv2_api.principal.id
  route_key          = "POST /api/v1/auth/login"
  target             = "integrations/${aws_apigatewayv2_integration.api_cluster[0].id}"
  authorization_type = "NONE"
}

# Tudo mais da aplicacao. As 52 rotas protegidas da matriz caem aqui, e e a
# unica rota do gateway com authorizer - ver authorizer.tf (issue #43).
#
# Requisicao sem header Authorization e recusada com 401 antes de sair do
# gateway; com header, o authorizer valida o token e so entao o trafego
# atravessa o VPC Link.
resource "aws_apigatewayv2_route" "api" {
  count = local.integrar_cluster ? 1 : 0

  api_id             = aws_apigatewayv2_api.principal.id
  route_key          = "ANY /api/v1/{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.api_cluster[0].id}"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt[0].id
}

# Alvo do monitor de uptime (issue #72). Apenas /health/live: o /health
# devolve description dos checks, que pode carregar mensagem de excecao do
# banco, e por isso fica interno. Ver a matriz de autorizacao.
resource "aws_apigatewayv2_route" "health_live" {
  count = local.integrar_cluster ? 1 : 0

  api_id             = aws_apigatewayv2_api.principal.id
  route_key          = "GET /health/live"
  target             = "integrations/${aws_apigatewayv2_integration.api_cluster[0].id}"
  authorization_type = "NONE"
}
