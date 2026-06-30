cluster_name       = "oficina-mecanica"
kubernetes_version = "v1.31.0"

control_plane_count = 1
worker_count        = 2

# Portas expostas no host (Windows/Mac/Linux)
api_host_port      = 8080   # localhost:8080 → NodePort 30080 da API
ingress_http_port  = 80     # localhost:80   → porta 80  do ingress
ingress_https_port = 443    # localhost:443  → porta 443 do ingress
