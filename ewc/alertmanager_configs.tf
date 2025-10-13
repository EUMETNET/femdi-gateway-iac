resource "kubernetes_secret" "alertmanager_default_smtp_password" {
  metadata {
    name      = "alertmanager-default-smtp-password"
    namespace = "cattle-monitoring-system"
  }

  data = {
    password = local.alert_manager_smtp_auth_password
  }

  type = "Opaque"

  depends_on = [rancher2_app_v2.rancher-monitoring]
}

# Default example Alertmanager Config
# sends all the received info, warning and critical alerts via email
resource "kubectl_manifest" "alertmanager_default_config" {

  # Only create the config if the SMTP username and password are set
  # So that we don't block the creation of other resources and can create the config later
  count = local.alert_manager_smtp_auth_username != "" && local.alert_manager_smtp_auth_password != "" ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1alpha1"
    kind       = "AlertmanagerConfig"
    metadata = {
      name      = "default-config"
      namespace = "cattle-monitoring-system"
    }
    spec = {
      receivers = [
        {
          name = "default-receiver"
          emailConfigs = [
            for email in split(",", local.alert_manager_email_recipients) : {
              authPassword = {
                name = "${kubernetes_secret.alertmanager_default_smtp_password.metadata.0.name}"
                key  = "password"
              }
              authUsername = "${local.alert_manager_smtp_auth_username}"
              from         = "${local.alert_manager_email_sender}"
              requireTLS   = true
              sendResolved = true
              smarthost    = "${local.alert_manager_smtp_host}"
              to           = email
              tlsConfig    = {}
            }
          ]
        }
      ]
      route = {
        groupBy       = []
        groupInterval = "5m"
        groupWait     = "30s"
        matchers = [
          {
            matchType = "=~"
            name      = "severity"
            value     = "^(info|warning|critical)$"
          }
        ]
        receiver       = "default-receiver"
        repeatInterval = "4h"
      }
    }
  })

  depends_on = [rancher2_app_v2.rancher-monitoring]
}
