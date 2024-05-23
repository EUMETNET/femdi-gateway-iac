output "load_balancer_io" {
  description = "Ip of load balancer created by nginx-ingress-controller"
  value = data.kubernetes_service.ingress-nginx-controller.ingress.ip
  sensitive   = true
}
