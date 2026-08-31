# Lambda authorizer do API Gateway (issue #43 / F3-09).
#
# Protege na borda as rotas classificadas como sensiveis na matriz de
# autorizacao. Ate aqui quem validava o token era so a API, no miolo: trafego
# nao autenticado atravessava o VPC Link e o cluster inteiro para so entao ser
# recusado. Agora ele para no gateway.
#
# A API .NET continua validando o mesmo token, de proposito - defesa em
# profundidade, como registrado na RFC-0002. Durante o desenvolvimento a API e
# acessada direto por port-forward, sem passar pelo gateway, e essa validacao e
# o que a protege nesse caminho.
#
# Lambda authorizer, e nao o authorizer JWT nativo do HTTP API: o nativo exige
# emissor OIDC com JWKS publico e assinatura assimetrica, e o token deste
# projeto e HS256 com segredo compartilhado. A comparacao completa esta na
# RFC-0002.

locals {
  # Mesmo motivo do lambda_auth_arn: a funcao e publicada pelo pipeline do
  # repositorio tech-challenge-lambda-auth, entao o ARN e montado em vez de lido
  # com `data aws_lambda_function`. Um data source apontando para funcao que
  # ainda nao existe derruba o `terraform plan`, e o plan bloqueia PR aqui.
  #
  # O nome casa com o que o ci.yml daquele repositorio publica. Divergir aqui
  # quebra a integracao silenciosamente: o gateway devolveria 500 sem dizer que
  # a funcao nao existe.
  authorizer_nome = coalesce(
    var.lambda_authorizer_nome,
    "${var.project}-authorizer-${var.ambiente}"
  )

  authorizer_arn = join("", [
    "arn:aws:lambda:",
    var.region,
    ":",
    data.aws_caller_identity.atual.account_id,
    ":function:",
    local.authorizer_nome
  ])
}

resource "aws_apigatewayv2_authorizer" "jwt" {
  count = local.integrar_cluster ? 1 : 0

  api_id          = aws_apigatewayv2_api.principal.id
  name            = "${local.nome}-jwt"
  authorizer_type = "REQUEST"

  # O URI de invocacao tem forma propria - nao e o ARN da funcao direto.
  authorizer_uri = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${local.authorizer_arn}/invocations"

  # Formato 2.0 com resposta simples: a funcao devolve { isAuthorized, context }
  # em vez de montar uma policy IAM. Decidido na RFC-0002.
  authorizer_payload_format_version = "2.0"
  enable_simple_responses           = true

  # O header Authorization e a chave do cache. Requisicao sem ele nem chega a
  # invocar a funcao: o gateway ja devolve 401.
  identity_sources = ["$request.header.Authorization"]

  # Cache de 300s, como a RFC-0002 define. Reduz invocacoes a praticamente uma
  # por token a cada cinco minutos.
  #
  # O preco: um token continua sendo aceito por ate cinco minutos depois de
  # expirar, servido do cache, sem a funcao ser consultada. O JwtTokenValidator
  # usa ClockSkew zero justamente para que toda invocacao real seja rigorosa -
  # o que ele nao pode fazer e apagar o cache.
  authorizer_result_ttl_in_seconds = var.authorizer_cache_ttl
}

# Sem esta permissao o gateway nao consegue chamar a funcao e devolve 500 em
# toda rota protegida. O source_arn restringe ao authorizer deste gateway.
resource "aws_lambda_permission" "gateway_invoca_authorizer" {
  count = local.integrar_cluster && var.lambdas_publicadas ? 1 : 0

  statement_id  = "AllowInvokeFromApiGatewayAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = local.authorizer_nome
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.principal.execution_arn}/authorizers/${aws_apigatewayv2_authorizer.jwt[0].id}"
}
