terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.9"
    }
  }

  backend "local" {
    path = "./terraform.tfstate"
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config" # Настроить под Minikube
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config" # Настроить под Minikube
  }
}

# Создание пространства имен для Istio
resource "kubernetes_namespace" "mesh_system" {
  metadata {
    name = "mesh-system"
  }
}

# Установка базовых компонентов Istio
resource "helm_release" "mesh_base" {
  name       = "mesh-base" # Уникальное имя релиза
  namespace  = "mesh-system" # Новый namespace для Istio
  chart      = "base"
  repository = "https://istio-release.storage.googleapis.com/charts"
  version    = "1.24.0"
}

# Установка Istio Discovery
resource "helm_release" "mesh_control_plane" {
  name       = "mesh-control-plane"
  namespace  = "mesh-system"
  chart      = "istiod"
  repository = "https://istio-release.storage.googleapis.com/charts"
  version    = "1.24.0"
  depends_on = [helm_release.mesh_base]
}

# Установка Ingress Gateway
resource "helm_release" "mesh_ingress" {
  name       = "mesh-ingress"
  namespace  = "mesh-system"
  chart      = "gateway"
  repository = "https://istio-release.storage.googleapis.com/charts"
  version    = "1.24.0"
  depends_on = [helm_release.mesh_control_plane]
}

# Развертывание HTTPD-приложения
resource "kubernetes_namespace" "example_app" {
  metadata {
    name = "example-app"
  }
}

resource "kubernetes_deployment" "web_server" {
  metadata {
    name      = "web-server"
    namespace = kubernetes_namespace.example_app.metadata[0].name
    labels = {
      app = "web-server"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "web-server"
      }
    }

    template {
      metadata {
        labels = {
          app = "web-server"
        }
      }

      spec {
        container {
          name  = "web-server"
          image = "httpd:2.4"
          port {
            container_port = 80
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "web_server_service" {
  metadata {
    name      = "web-server"
    namespace = kubernetes_namespace.example_app.metadata[0].name
    labels = {
      app = "web-server"
    }
  }

  spec {
    selector = {
      app = "web-server"
    }

    port {
      port        = 80
      target_port = 80
    }

    type = "ClusterIP"
  }
}

# Настройка Gateway и VirtualService для Istio
resource "kubernetes_manifest" "mesh_web_gateway" {
  manifest = {
    apiVersion = "networking.istio.io/v1alpha3"
    kind       = "Gateway"
    metadata = {
      name      = "web-gateway"
      namespace = kubernetes_namespace.example_app.metadata[0].name
    }
    spec = {
      selector = {
        istio = "ingressgateway"
      }
      servers = [
        {
          port = {
            number   = 80
            name     = "http"
            protocol = "HTTP"
          }
          hosts = ["*"]
        }
      ]
    }
  }
}

resource "kubernetes_manifest" "mesh_web_virtualservice" {
  manifest = {
    apiVersion = "networking.istio.io/v1alpha3"
    kind       = "VirtualService"
    metadata = {
      name      = "web-service"
      namespace = kubernetes_namespace.example_app.metadata[0].name
    }
    spec = {
      hosts = ["*"]
      gateways = ["web-gateway"]
      http = [
        {
          route = [
            {
              destination = {
                host = "web-server.example-app.svc.cluster.local"
                port = {
                  number = 80
                }
              }
            }
          ]
        }
      ]
    }
  }
}
