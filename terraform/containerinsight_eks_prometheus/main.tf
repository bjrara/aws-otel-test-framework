# ------------------------------------------------------------------------
# Copyright 2020 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License").
# You may not use this file except in compliance with the License.
# A copy of the License is located at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# or in the "license" file accompanying this file. This file is distributed
# on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
# express or implied. See the License for the specific language governing
# permissions and limitations under the License.
# -------------------------------------------------------------------------

# creating a eks cluster takes around 10 minutes typically.
# so in the eks/k8s test, we need tester to provide the cluster instead of creating it in terraform
# so that we can shorten the execution time

terraform {
  required_providers {
    kubernetes = {
      version = "~> 1.13"
    }
  }
}

module "common" {
  source = "../common"

  aoc_image_repo = var.aoc_image_repo
  aoc_version    = var.aoc_version
}

# region
provider "aws" {
  region = var.region
}

# get eks cluster by name
data "aws_eks_cluster" "testing_cluster" {
  name = var.eks_cluster_name
}

data "aws_eks_cluster_auth" "testing_cluster" {
  name = var.eks_cluster_name
}

provider "kubernetes" {
  // Note: copy from eks module. Please avoid use shorted-lived tokens when running locally.
  // For more information: https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs#exec-plugins
  host                   = data.aws_eks_cluster.testing_cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.testing_cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.testing_cluster.token
  load_config_file       = false
}

data "template_file" "kubeconfig_file" {
  template = file("./kubeconfig.tpl")
  vars = {
    CA_DATA : data.aws_eks_cluster.testing_cluster.certificate_authority[0].data
    SERVER_ENDPOINT : data.aws_eks_cluster.testing_cluster.endpoint
    TOKEN = data.aws_eks_cluster_auth.testing_cluster.token
  }
}

resource "local_file" "kubeconfig" {
  filename = "kubeconfig"
  content  = data.template_file.kubeconfig_file.rendered
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.testing_cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.testing_cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.testing_cluster.token
  }
}


# create a unique namespace for each run
resource "kubernetes_namespace" "aoc_ns" {
  metadata {
    name = "aoc-ns-${module.common.testing_id}"
  }
}

resource "kubernetes_service_account" "aoc_role" {
  metadata {
    name      = "aoc-role-${module.common.testing_id}"
    namespace = kubernetes_namespace.aoc_ns.metadata[0].name
  }
  automount_service_account_token = true
}

resource "kubernetes_cluster_role_binding" "aoc_role_binding" {
  metadata {
    name = "aoc-role-binding-${module.common.testing_id}"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "aoc-role-${module.common.testing_id}"
    namespace = kubernetes_namespace.aoc_ns.metadata[0].name
  }
}

resource "kubernetes_config_map" "aoc_configmap" {
  metadata {
    name      = "otel-agent-conf"
    namespace = kubernetes_namespace.aoc_ns.metadata[0].name
  }
  data = {
    "otel-agent-config" = "${file("${var.testcase}/otel-agent-config.yaml")}"
  }
}

resource "kubernetes_daemonset" "aoc_ds" {
  metadata {
    name      = "aoc"
    namespace = kubernetes_namespace.aoc_ns.metadata[0].name
    labels = {
      app = "aoc"
    }
  }

  spec {
    selector {
      match_labels = {
        app = "aoc"
      }
    }

    template {
      metadata {
        labels = {
          app = "aoc"
        }
      }

      spec {
        service_account_name            = "aoc-role-${module.common.testing_id}"
        automount_service_account_token = true
        # aoc
        container {
          name  = "aoc"
          image = module.common.aoc_image
          command = [
            "/awscollector",
          "--config=/conf/otel-agent-config.yaml"]
          image_pull_policy = "Always"
          env {
            name  = "AWS_REGION"
            value = var.region
          }
          env {
            name = "K8S_NODE_NAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }
          env {
            name = "HOST_IP"
            value_from {
              field_ref {
                field_path = "status.hostIP"
              }
            }
          }
          env {
            name = "HOST_NAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }
          env {
            name = "K8S_NAMESPACE"
            value_from {
              field_ref {
                field_path = "metadata.namespace"
              }
            }
          }
          resources {
            requests {
              cpu    = "0.2"
              memory = "256Mi"
            }
          }
          volume_mount {
            name       = "rootfs"
            mount_path = "/rootfs"
            read_only  = true
          }
          volume_mount {
            name       = "dockersock"
            mount_path = "/var/run/docker.sock"
            read_only  = true
          }
          volume_mount {
            name       = "varlibdocker"
            mount_path = "/var/lib/docker"
            read_only  = true
          }
          volume_mount {
            name       = "sys"
            mount_path = "/sys"
            read_only  = true
          }
          volume_mount {
            name       = "devdisk"
            mount_path = "/dev/disk"
            read_only  = true
          }
          volume_mount {
            name       = "otel-agent-config-vol"
            mount_path = "/conf"
          }
        }
        volume {
          name = "otel-agent-config-vol"
          config_map {
            name = "otel-agent-conf"
            items {
              key  = "otel-agent-config"
              path = "otel-agent-config.yaml"
            }
          }
        }
        volume {
          name = "rootfs"
          host_path {
            path = "/"
          }
        }
        volume {
          name = "dockersock"
          host_path {
            path = "/var/run/docker.sock"
          }
        }
        volume {
          name = "varlibdocker"
          host_path {
            path = "/var/lib/docker"
          }
        }
        volume {
          name = "sys"
          host_path {
            path = "/sys"
          }
        }
        volume {
          name = "devdisk"
          host_path {
            path = "/dev/disk/"
          }
        }
      }
    }
  }
}

resource "kubernetes_deployment" "standalone_aoc_deployment" {
  metadata {
    name      = "aoc"
    namespace = kubernetes_namespace.aoc_ns.metadata[0].name
    labels = {
      app = "aoc"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "aoc"
      }
    }

    template {
      metadata {
        labels = {
          app = "aoc"
        }
      }

      spec {
        service_account_name            = "aoc-role-${module.common.testing_id}"
        automount_service_account_token = true
        # aoc
        container {
          name              = "aoc"
          image             = module.common.aoc_image
          image_pull_policy = "Always"
          args = [
            "--config",
          "/etc/eks/prometheus/config-all.yaml"]
          env {
            name  = "AWS_REGION"
            value = var.region
          }
          env {
            name  = "OTEL_RESOURCE_ATTRIBUTES"
            value = "ClusterName=${var.eks_cluster_name}"
          }
          resources {
            requests {
              cpu    = "0.2"
              memory = "256Mi"
            }
          }
        }
      }
    }
  }
}

##########################################
# Validation
##########################################
module "validator" {
  source = "../validation"

  validation_config = var.validation_config
  region            = var.region
  testing_id        = module.common.testing_id
  metric_namespace  = "${module.common.otel_service_namespace}/${module.common.otel_service_name}"

  aws_access_key_id     = var.aws_access_key_id
  aws_secret_access_key = var.aws_secret_access_key
}