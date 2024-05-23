output "load_balancer_io" {
  description = "Ip of load balancer created by nginx-ingress-controller"
  value       = data.kubernetes_service.ingress-nginx-controller.status[0].load_balancer[0].ingress[0].ip
  sensitive   = true
}
