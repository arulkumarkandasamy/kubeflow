#!/usr/bin/env bash

function kustomize_build() {
    local INPUT_LOCATION="${1}"
    IFS=$'\n'
    for kustomize_folder in "${INPUT_LOCATION}"/kustomize/*; do
        file_name="$(basename "$kustomize_folder")"
        local build_location=./instance/build/"${file_name}"
        mkdir -p "${build_location}"
        kustomize build --load_restrictor none -o "${build_location}"  "${kustomize_folder}"
    done
}

function apply_raw_manifests() {
    local BASE_DIR=./deployments
    local MANIFEST_LOCATION="${1}"
    local KUBECONFIG="${2}"
    local BUILD_DIR="${MANIFEST_LOCATION}/build"

    kubectl apply -f "${BUILD_DIR}"/istio/~g_v1_namespace_istio-system.yaml
    apply_manifests_in_order "${BUILD_DIR}"/namespaces ${KUBECONFIG}
    apply_manifests_in_order "${BUILD_DIR}"/psp ${KUBECONFIG}
    apply_manifests_in_order "${BUILD_DIR}"/istio ${KUBECONFIG}
    apply_manifests_in_order "${BUILD_DIR}"/application ${KUBECONFIG}
    apply_manifests_in_order "${BUILD_DIR}"/kubeflow-istio ${KUBECONFIG}
    apply_manifests_in_order "${BUILD_DIR}"/kubeflow-istio-local-gateway ${KUBECONFIG}
    apply_manifests_in_order "${BUILD_DIR}"/metacontroller ${KUBECONFIG}
    apply_manifests_in_order "${BUILD_DIR}"/gpu-driver ${KUBECONFIG}

    # Dex Auth
    if [[ -d "${BUILD_DIR}/dex-auth" ]]
    then
        kubectl apply -f "${BUILD_DIR}"/dex-auth/~g_v1_namespace_auth.yaml --kubeconfig=${KUBECONFIG}
        apply_manifests_in_order "${BUILD_DIR}"/dex-auth ${KUBECONFIG}
        apply_manifests_in_order "${BUILD_DIR}"/oidc-authservice ${KUBECONFIG}
    fi

    # Apply the namespace first
    kubectl apply -f "${BUILD_DIR}"/knative/~g_v1_namespace_knative-serving.yaml --kubeconfig=${KUBECONFIG}
    apply_manifests_in_order "${BUILD_DIR}"/knative ${KUBECONFIG}

    apply_manifests_in_order "${BUILD_DIR}"/cert-manager-crds ${KUBECONFIG}
    apply_manifests_in_order "${BUILD_DIR}"/cert-manager-kube-system ${KUBECONFIG}
    apply_manifests_in_order "${BUILD_DIR}"/cert-manager ${KUBECONFIG}

    # We need to wait for certmanager webhook to be available other wise we will get failures
    kubectl -n cert-manager wait --for=condition=Available --timeout=600s deploy cert-manager-webhook --kubeconfig=${KUBECONFIG}
    kubectl -n cert-manager wait --for=condition=Available --timeout=600s deploy cert-manager --kubeconfig=${KUBECONFIG}
    kubectl -n cert-manager wait --for=condition=Available --timeout=600s deploy cert-manager-cainjector --kubeconfig=${KUBECONFIG}

    # GCP IAP Auth
    if [[ -d "${BUILD_DIR}/iap-ingress" ]]
    then
        apply_manifests_in_order ./"${BUILD_DIR}"/iap-ingress ${KUBECONFIG}
        # First check annotation before applying
        kubectl annotate service istio-ingressgateway -n istio-system beta.cloud.google.com/backend-config='{"ports": {"http2":"iap-backendconfig"}}' --kubeconfig=${KUBECONFIG}
    fi

    apply_manifests_in_order "${BUILD_DIR}"/kubeflow-apps ${KUBECONFIG}
    # Create the kubeflow-issuer last to give cert-manager time deploy
    apply_manifests_in_order "${BUILD_DIR}"/kubeflow-self-issuer ${KUBECONFIG}
}

function apply_manifests_in_order {
    local dir=${1}
    local kubeconfig=${2}
    local prereq_manifests=$(ls ${dir} | grep "~g")
    for manifest in ${prereq_manifests}; do
        kubectl apply -f ./${dir}/${manifest} --kubeconfig=${kubeconfig}
    done
    local other_manifests=$(ls ${dir} | grep -v "~g")
    for manifest in ${other_manifests}; do
        kubectl apply -f ${dir}/${manifest} --kubeconfig=${kubeconfig}
    done
}

function create_gsa_if_not_present {
  local name=${1}
  local already_present=$(gcloud iam service-accounts list --filter='name:'$name'' --format='value(name)')
  if [ -n "$already_present" ]; then
    echo "Service account $name already exists"
  else
    gcloud iam service-accounts create $name
  fi
}

# Bind KSA to GSA through workload identity.
# Documentation: https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity
function bind_gsa_and_ksa {
  local gsa=${1}
  local ksa=${2}
  local project=${3:-$PROJECT_ID}
  local gsa_full="$gsa@$project.iam.gserviceaccount.com"
  local namespace=${4:-$NAMESPACE}

  gcloud iam service-accounts add-iam-policy-binding $gsa_full \
    --member="serviceAccount:$project.svc.id.goog[$namespace/$ksa]" \
    --role="roles/iam.workloadIdentityUser" \
    > /dev/null # hide verbose output
  kubectl annotate serviceaccount \
    --namespace $namespace \
    --overwrite \
    $ksa \
    iam.gke.io/gcp-service-account=$gsa_full
  echo "* Bound KSA $ksa in namespace $namespace to GSA $gsa_full"
}

# This can be used to programmatically verify workload identity binding grants corresponding GSA
# permissions successfully.
# Usage: verify_workload_identity_binding $KSA $NAMESPACE
#
# If you want to verify manually, use the following command instead:
# kubectl run test-$RANDOM --rm -it --restart=Never \
#     --image=google/cloud-sdk:slim \
#     --serviceaccount $ksa \
#     --namespace $namespace \
#     -- /bin/bash
# It connects you to a pod using specified KSA running an image with gcloud and gsutil CLI tools.
function verify_workload_identity_binding {
  local ksa=${1}
  local namespace=${2}
  local max_attempts=10
  local workload_identity_is_ready=false
  for i in $(seq 1 ${max_attempts})
  do
    workload_identity_is_ready=true
    kubectl run test-$RANDOM --rm -i --restart=Never \
        --image=google/cloud-sdk:slim \
        --serviceaccount $ksa \
        --namespace $namespace \
        -- gcloud auth list || workload_identity_is_ready=false
    kubectl run test-$RANDOM --rm -i --restart=Never \
        --image=google/cloud-sdk:slim \
        --serviceaccount $ksa \
        --namespace $namespace \
        -- gsutil ls gs:// || workload_identity_is_ready=false
    if [ "$workload_identity_is_ready" = true ]; then
      break
    fi
  done
  if [ ! "$workload_identity_is_ready" = true ]; then
    echo "Workload identity bindings are not ready after $max_attempts attempts"
    return 1
  fi
}

function connect_to_gke() {
    local project_id=$1
    local cluster=$2
    tunnel_script="$(dirname $0)/connect-to-gke.sh"
    "${tunnel_script}" -p "${project_id}" -c "${cluster}" -x
    "${tunnel_script}" -p "${project_id}" -c "${cluster}"
}

#function