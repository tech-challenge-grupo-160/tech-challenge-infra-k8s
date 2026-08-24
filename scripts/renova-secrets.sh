#!/usr/bin/env bash
#
# Renova os secrets da AWS nos repositorios do projeto.
#
# As credenciais do AWS Academy Learner Lab sao temporarias e trocam a cada
# sessao (~4h). Este script le o perfil local e publica nos repositorios sem
# em nenhum momento imprimir os valores.
#
# Uso:
#   ./scripts/renova-secrets.sh              # renova nos 4 repositorios
#   ./scripts/renova-secrets.sh --check      # so mostra o estado atual
#   ./scripts/renova-secrets.sh --dry-run    # mostra o que faria
#
# Variaveis:
#   AWS_PROFILE   perfil do ~/.aws/credentials (padrao: default)
#   AWS_REGION    regiao (padrao: us-east-1, unica do Learner Lab)

set -euo pipefail

ORG="tech-challenge-grupo-160"
REPOS=(
  tech-challenge-oficina-mecanica
  tech-challenge-lambda-auth
  tech-challenge-infra-k8s
  tech-challenge-infra-database
)
PERFIL="${AWS_PROFILE:-default}"
REGIAO="${AWS_REGION:-us-east-1}"
MODO="aplicar"

for arg in "$@"; do
  case "$arg" in
    --check)   MODO="verificar" ;;
    --dry-run) MODO="simular" ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Argumento desconhecido: $arg" >&2; exit 1 ;;
  esac
done

vermelho() { printf '\033[31m%s\033[0m\n' "$1"; }
verde()    { printf '\033[32m%s\033[0m\n' "$1"; }
amarelo()  { printf '\033[33m%s\033[0m\n' "$1"; }

# ------------------------------------------------------------------ requisitos
# gh e sempre necessario. O aws so nos modos que leem credencial local -
# assim o --check funciona de qualquer maquina, inclusive sem AWS CLI.
if ! command -v gh >/dev/null 2>&1; then
  vermelho "ERRO: 'gh' nao encontrado no PATH."
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  vermelho "ERRO: gh nao autenticado. Rode: gh auth login"
  exit 1
fi

if [ "$MODO" != "verificar" ] && ! command -v aws >/dev/null 2>&1; then
  vermelho "ERRO: 'aws' nao encontrado no PATH."
  echo "Necessario para ler as credenciais locais. Use --check para so consultar."
  exit 1
fi

# ------------------------------------------------------------------ modo check
if [ "$MODO" = "verificar" ]; then
  echo "Secrets e variaveis por repositorio (nomes e datas, nunca valores):"
  for r in "${REPOS[@]}"; do
    echo
    echo "  $r"
    gh secret list --repo "$ORG/$r" 2>/dev/null | sed 's/^/    /' || echo "    (sem acesso)"
    gh variable list --repo "$ORG/$r" 2>/dev/null | sed 's/^/    /' || true
  done
  exit 0
fi

# ------------------------------------------------------------------ credenciais
KEY_ID="$(aws configure get aws_access_key_id --profile "$PERFIL" 2>/dev/null || true)"
SECRET="$(aws configure get aws_secret_access_key --profile "$PERFIL" 2>/dev/null || true)"
TOKEN="$(aws configure get aws_session_token --profile "$PERFIL" 2>/dev/null || true)"

if [ -z "$KEY_ID" ] || [ -z "$SECRET" ]; then
  vermelho "ERRO: perfil '$PERFIL' sem credenciais em ~/.aws/credentials."
  echo "Copie o bloco de AWS Details -> AWS CLI no painel do Learner Lab."
  exit 1
fi

if [ -z "$TOKEN" ]; then
  vermelho "ERRO: nao ha aws_session_token no perfil '$PERFIL'."
  echo "Credenciais do Learner Lab sempre tem session token. Sem ele, provavelmente"
  echo "sao chaves de longa duracao - que nao devem ser usadas neste projeto."
  exit 1
fi

# Confirma que a credencial funciona antes de publicar em quatro lugares.
if ! IDENT="$(aws sts get-caller-identity --profile "$PERFIL" --query 'Arn' --output text 2>&1)"; then
  vermelho "ERRO: credenciais invalidas ou expiradas."
  echo "$IDENT" | head -2
  echo
  echo "No painel do Learner Lab: End Lab, depois Start Lab, e copie o bloco novo."
  exit 1
fi
verde "Credenciais validas: $(echo "$IDENT" | sed 's/[0-9]\{12\}/<conta>/')"
echo "Regiao: $REGIAO   Perfil: $PERFIL"
echo

if [ "$MODO" = "simular" ]; then
  amarelo "Modo simulacao - nada sera alterado."
  for r in "${REPOS[@]}"; do
    echo "  $ORG/$r <- AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN, AWS_REGION"
  done
  exit 0
fi

# ------------------------------------------------------------------ publicacao
falhas=0
for r in "${REPOS[@]}"; do
  printf '  %-38s ' "$r"
  ok=true
  # printf sem newline evita que o valor caia em historico de shell
  printf '%s' "$KEY_ID" | gh secret set AWS_ACCESS_KEY_ID     --repo "$ORG/$r" >/dev/null 2>&1 || ok=false
  printf '%s' "$SECRET" | gh secret set AWS_SECRET_ACCESS_KEY --repo "$ORG/$r" >/dev/null 2>&1 || ok=false
  printf '%s' "$TOKEN"  | gh secret set AWS_SESSION_TOKEN     --repo "$ORG/$r" >/dev/null 2>&1 || ok=false
  gh variable set AWS_REGION --body "$REGIAO" --repo "$ORG/$r" >/dev/null 2>&1 || ok=false
  if $ok; then verde "ok"; else vermelho "falhou"; falhas=$((falhas + 1)); fi
done

echo
if [ "$falhas" -gt 0 ]; then
  vermelho "$falhas repositorio(s) falharam. Verifique se voce tem permissao de admin neles."
  exit 1
fi
verde "Secrets renovados nos ${#REPOS[@]} repositorios."
amarelo "Validos ate o fim da sessao do lab (~4h). Rode de novo na proxima sessao."
