# The following outputs allow authentication and connectivity to the GKE Cluster
# by using certificate-based authentication.
output "client_certificate" {
  value = "${google_container_cluster.cluster.master_auth.0.client_certificate}"
}

output "client_key" {
  value = "${google_container_cluster.cluster.master_auth.0.client_key}"
}

output "cluster_ca_certificate" {
  value = "${google_container_cluster.cluster.master_auth.0.cluster_ca_certificate}"
}

output "cluster_endpoint" {
  value = "https://${google_container_cluster.cluster.endpoint}"
}
output "ingress_ip" {
  value = "http://${google_compute_global_address.nginx_app_address.address}"
}

output "app_url" {
  value = "https://${var.nginx_url}"
}
