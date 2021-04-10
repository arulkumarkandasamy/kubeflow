#!/bin/bash
#set -euxo pipefail

BASE_DIR=~/projects/kubeflow/deployments/
KF_NAME="${1}"
BUILD_DIR="${BASE_DIR}/${KF_NAME}/build"

kubectl delete -f "${BUILD_DIR}"/application
kubectl delete -f "${BUILD_DIR}"/kubeflow-istio
kubectl delete -f "${BUILD_DIR}"/kubeflow-istio-local-gateway
kubectl delete -f "${BUILD_DIR}"/metacontroller
# Dex Auth
kubectl delete -f "${BUILD_DIR}"/oidc-authservice
kubectl delete -f "${BUILD_DIR}"/dex-auth
kubectl delete -f "${BUILD_DIR}"/gpu-driver
# GCP IAP Ingress
#kubectl delete -f ./"${BUILD_DIR}"/cloud-endpoints
#kubectl delete -f ./"${BUILD_DIR}"/iap-ingress
kubectl delete -f "${BUILD_DIR}"/knative/~g_v1_namespace_knative-serving.yaml
kubectl delete --recursive=true -f "${BUILD_DIR}"/knative
kubectl delete -f "${BUILD_DIR}"/cert-manager-crds
kubectl delete -f "${BUILD_DIR}"/cert-manager-kube-system
kubectl delete -f "${BUILD_DIR}"/cert-manager
kubectl delete -f "${BUILD_DIR}"/kubeflow-apps
kubectl delete -f "${BUILD_DIR}"/kubeflow-self-issuer