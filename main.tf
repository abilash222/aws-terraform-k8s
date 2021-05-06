variable "k8s_machine_type" {
  description = "Machine type to use for the general-purpose node pool. See https://cloud.google.com/compute/docs/machine-types"
}

variable "k8s_min_node_count" {
  description = "The minimum number of nodes PER ZONE in the general-purpose node pool"
  default = 1
}

variable "k8s_max_node_count" {
  description = "The maximum number of nodes PER ZONE in the general-purpose node pool"
  default = 4
}

variable "k8s_username" {
  description = "k8s username to login cluster"
}
variable "k8s_password" {
  description = "k8s username to login cluster"
}

variable "nginx_url" {
  description = "nginx dns name to access"
}
  
# This step creates a GKE cluster
resource "google_container_cluster" "cluster" {
  name     = "${var.project}-cluster"
  location = "${var.region}"

  remove_default_node_pool = true
  initial_node_count = 1

  master_auth {
    username = "${var.k8s_username}"
    password = "${var.k8s_password}"
  
    client_certificate_config {
      issue_client_certificate = true
    }
  }

  addons_config {
    network_policy_config {
      disabled = "false"
    }
  }

  network_policy {
    enabled = "true"
    provider = "CALICO"
  }
}

resource "google_container_node_pool" "cluster" {
  name       = "${var.project}-cluster"
  location   = "${var.region}"
  cluster    = "${google_container_cluster.cluster.name}"

  management { 
    auto_repair = "true"
    auto_upgrade = "true"
  }

  autoscaling { 
    min_node_count = "${var.k8s_min_node_count}"
    max_node_count = "${var.k8s_max_node_count}"
  }
  initial_node_count = "${var.k8s_min_node_count}"

  node_config {
    machine_type = "${var.k8s_machine_type}"

    metadata = {
      disable-legacy-endpoints = "true"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/devstorage.read_only"
    ]
  }
}


# This step creates a static IP and a DNS record for app domain name 
resource "google_compute_global_address" "nginx_app_address" {
  name = "nginx-hello"
  description = "nginx app zone"
}

resource "google_dns_record_set" "frontend" {
  name = "lb.${google_dns_managed_zone.prod.dns_name}"
  type = "A"
  ttl  = 300

  managed_zone = google_dns_managed_zone.prod.name
  rrdatas = [google_compute_global_address.nginx_app_address.address]
}

resource "google_dns_managed_zone" "prod" {
  name     = "prod"
  dns_name = "${var.nginx_url}."
}

provider "kubernetes" {
  load_config_file = "false"
  host = "https://${google_container_cluster.cluster.endpoint}"
  username = "${var.k8s_username}"
  password = "${var.k8s_password}"
  insecure = true
}

# This step does the nginx-hello app deployment
resource "kubernetes_deployment" "nginx-hello" {
  depends_on = ["kubernetes_deployment.nginx-hello"]
  metadata {
    name = "terraform-nginx-hello"
    labels = {
      app = "nginx-hello"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "nginx-hello"
      }
    }

    template {
      metadata {
        labels = {
          app = "nginx-hello"
        }
      }

      spec {
        container {
          image = "nginxdemos/hello"
          name  = "nginx-hello"

          resources {
            limits {
              cpu    = "1"
              memory = "512Mi"
            }
            requests {
              cpu    = "250m"
              memory = "256Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/nginx_status"
              port = 80
          }
            initial_delay_seconds = 3
            period_seconds        = 3
          }
        }
      }
    }
  }
}

# Below step creates nginx-hello app service to access
resource "kubernetes_service" "nginx-hello" {
  depends_on = ["google_container_node_pool.cluster"]
  metadata {
    name = "nginx-hello"
  }
  spec {
    selector = {
      app = "${kubernetes_deployment.nginx-hello.metadata.0.labels.app}"
    }
    session_affinity = "ClientIP"
    port {
      port        = 80
      target_port = 80
    }
    type = "LoadBalancer"
  }
}

provider "helm" {
  kubernetes {
    host = "https://${google_container_cluster.cluster.endpoint}"
    insecure = true
    username = "${var.k8s_username}"
    password = "${var.k8s_password}"
  }
}
data "helm_repository" "nginx-ingress" {
  name = "nginx-ingress"
  url  = "https://helm.nginx.com/stable"
}


# Below step installs nginx-ingress using helm
resource "helm_release" "nginx-ingress" {
  name  = "nginx-ingress"
  repository = data.helm_repository.nginx-ingress.metadata[0].name
  chart = "nginx-ingress"
  depends_on = ["google_container_node_pool.cluster"]
  set {
    name  = "controller.metrics.service.loadBalancerIP"
    value = "${google_compute_global_address.nginx_app_address.address}"
  }
}
resource "null_resource" "k8s_config" {
  depends_on = ["google_container_node_pool.cluster"]
  provisioner "local-exec" {
    command = " /bin/bash gcloud container clusters get-credentials ${google_container_cluster.cluster.name} --region ${var.region}"
  }
}

# Below step creates custom resource definition for handling ingress certificate
resource "null_resource" "custom-resource-definition" {
  depends_on = ["null_resource.k8s_config"]
  provisioner "local-exec" {
#    command = "kubectl--server https://${google_container_cluster.cluster.endpoint} --username=${var.k8s_username} --password=${var.k8s_password} apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v0.14.0/cert-manager-legacy.crds.yaml"
    command = "kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v0.14.0/cert-manager-legacy.crds.yaml"
  }
}


# Below step deploy certificate manager using helm
data "helm_repository" "cert-manager" {
    name = "jetstack"
    url  = "https://charts.jetstack.io"
}

resource "helm_release" "cert-manager" {
  name = "cert-manager"
  repository = data.helm_repository.cert-manager.metadata[0].name
  chart = "cert-manager"
  namespace = "kube-system"
  version = "v0.14.0"
  depends_on = ["helm_release.nginx-ingress"]
}

resource "null_resource" "cluster-issuer" {
  depends_on = ["helm_release.cert-manager"]
  provisioner "local-exec" {
    command = "kubectl apply -f letsencrypt-issuer.yaml"
  }
}

resource "kubernetes_ingress" "nginx-hello" {
  metadata {
    name = "nginx-hello-ingress"

    annotations  = {
      "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
      "cert-manager.io/acme-http01-edit-in-place" = "true"
    }
  }

  spec {
    backend {
      service_name = "${kubernetes_service.nginx-hello.metadata.0.name}"
      service_port = 80
    }

    rule {
      host = "nginx-hello-test.com"
      http {
        path {
          backend {
            service_name = "${kubernetes_service.nginx-hello.metadata.0.name}"
            service_port = 80
          }

          path = "/*"
        }

      }
    }

    tls {
      secret_name = "nginx-hello"
      hosts = ["${var.nginx_url}"]
    }
  }
}
