#!/usr/bin/env bash

set -euxo pipefail

IMAGE="$1"
docker build . --build-arg INPUT_IMAGE="$IMAGE" --tag ${IMAGE/gcr.io/gcr.io\/vf-mc2dev-ca-lab\/mirror}
docker push ${IMAGE/gcr.io/gcr.io\/vf-mc2dev-ca-lab\/mirror}