output "dev-portal_keycloak_secret" {
  description = "Dev-portal's secret to authenticate with Keycloak"
  value       = random_password.keycloak-dev-portal-secret.result
  sensitive   = true
}

