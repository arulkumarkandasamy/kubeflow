#!/bin/bash

set -euo pipefail

INPUT_LOCATION="${1}"

for file in "${INPUT_LOCATION}"/kustomize/*; do
    file_name="$(basename "$file")"
    mkdir -p "${INPUT_LOCATION}"/build/"${file_name}"
    kustomize build --load_restrictor none -o "${INPUT_LOCATION}"/build/"${file_name}"  "$file"
done
mkdir -p "${INPUT_LOCATION}"/build/kf-prereq/
mv "${INPUT_LOCATION}"/build/kubeflow-apps/\~g_v1_* "${INPUT_LOCATION}"/build/kf-prereq/