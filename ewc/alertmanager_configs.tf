resource "kubernetes_secret" "alertmanager_default_smtp_password" {
  metadata {
    name      = "alertmanager-default-smtp-password"
    namespace = "cattle-monitoring-system"
  }

  data = {
    password = data.aws_ssm_parameter.alert_smtp_auth_password.value
  }

  type = "Opaque"

  depends_on = [rancher2_app_v2.rancher-monitoring]
}

# Default example Alertmanager Config
# sends all the received info, warning and critical alerts via email
resource "kubectl_manifest" "alertmanager_default_config" {

  # Only create the config if the SMTP username and password are set
  # So that we don't block the creation of other resources and can create the config later
  count = data.aws_ssm_parameter.alert_smtp_auth_username.value != "" && data.aws_ssm_parameter.alert_smtp_auth_password.value != "" ? 1 : 0

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
            for email in split(",", data.aws_ssm_parameter.alert_email_recipients.value) : {
              authPassword = {
                name = "${kubernetes_secret.alertmanager_default_smtp_password.metadata.0.name}"
                key  = "password"
              }
              authUsername = "${data.aws_ssm_parameter.alert_smtp_auth_username.value}"
              from         = "${data.aws_ssm_parameter.alert_email_sender.value}"
              requireTLS   = true
              sendResolved = true
              smarthost    = "${data.aws_ssm_parameter.alert_smtp_host.value}"
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
