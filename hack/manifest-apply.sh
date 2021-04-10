#!/usr/bin/env bash

set -euo pipefail

source "$(dirname $0)/utils.sh"
KF_NAME="${1}"
PROJECT="${2}"
CLUSTER_NAME="${3}"
KUBECONFIG=$(connect_to_gke ${PROJECT} ${CLUSTER_NAME} | grep export)
KUBECONFIG=${KUBECONFIG##"export KUBECONFIG="}
apply_raw_manifests ${KF_NAME} ${PROJECT} ${KUBECONFIG}

#gcloud iam service-accounts add-iam-policy-binding test-admin-sa@vf-mc2dev-ca-lab.iam.gserviceaccount.com \
#    --member="serviceAccount:vf-mc2dev-ca-lab.svc.id.goog[istio-system/kf-admin]" \
#    --role="roles/iam.workloadIdentityUser" \
#    --project=vf-mc2dev-ca-lab
