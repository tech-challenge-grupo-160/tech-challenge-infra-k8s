cluster_name       = "oficina-mecanica"
kubernetes_version = "v1.31.0"

control_plane_count = 1
worker_count        = 2

# Portas expostas no host (Windows)
api_host_port      = 8080
ingress_http_port  = 80
ingress_https_port = 443

# Banco de dados
postgres_user = "postgres"
postgres_pas  = "suasenha"
postgres_db   = "oficina_mecanica"

# JWT — use uma chave forte em produção (mínimo 32 caracteres)
jwt_secret_key = "suasenha"