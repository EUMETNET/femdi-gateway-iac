data "aws_ssm_parameter" "default_workspace_preset_id" {
  name = "/${var.cluster_name}/geoweb/default_workspace_preset_id"
}