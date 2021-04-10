#!/usr/bin/env bash

set -euxo pipefail

#IMAGES="$1"

for IMAGE in gcr.io/knative-releases/knative.dev/serving/cmd/autoscaler-hpa:v0.14.3 gcr.io/knative-releases/knative.dev/serving/cmd/autoscaler:v0.14.3 gcr.io/knative-releases/knative.dev/serving/cmd/networking/istio:v0.14.3 gcr.io/knative-releases/knative.dev/serving/cmd/webhook:v0.14.3 gcr.io/knative-releases/knative.dev/serving/cmd/controller:v0.14.3 gcr.io/knative-releases/knative.dev/serving/cmd/queue:v0.14.3
do
    echo "$IMAGE"
   docker build . --build-arg INPUT_IMAGE="$IMAGE" --tag ${IMAGE/gcr.io/gcr.io\/vf-mc2dev-ca-lab\/mirror}
   docker push ${IMAGE/gcr.io/gcr.io\/vf-mc2dev-ca-lab\/mirror}
done
