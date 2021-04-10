#!/usr/bin/env bash

set -euxo pipefail

BASE_DIR=./deployments/
KF_NAME="${1}"
PROJECT="${2}"
PROJECT_DIR="$(pwd)"
CONFIG_URI=./configs/${PROJECT}/"${KF_NAME}"/kfdef.yaml
VARS_DIR=./configs/${PROJECT}/"${KF_NAME}"/vars/
KF_DIR="${BASE_DIR}/${PROJECT}/${KF_NAME}"

# Create your Kubeflow configurations:
mkdir -p "${KF_DIR}"
cp "${CONFIG_URI}" "${KF_DIR}"
cd "${KF_DIR}"
sed -i '' 's@${PROJECT_ROOT}@'"${PROJECT_DIR}"'@'  $(basename "${CONFIG_URI}")
kfctl build -V -f "$(basename ${CONFIG_URI})"

# Get configuration
cd "${PROJECT_DIR}"
echo "Copying environment config"
rsync -av ${VARS_DIR} "${KF_DIR}"/.cache/manifests/stacks/vf-stack/