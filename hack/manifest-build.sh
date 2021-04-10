#!/usr/bin/env bash

set -euo pipefail

source "$(dirname $0)/utils.sh"
KF_NAME="${1}"
PROJECT="${2}"
create_configuration ${KF_NAME} ${PROJECT}
kustomize_build ./deployments/${PROJECT}/${KF_NAME}