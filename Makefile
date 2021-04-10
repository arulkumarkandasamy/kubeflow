SHELL := /bin/bash

ifndef ENVIRONMENT
$(info Current environment is not set, setting from branch)
ENVIRONMENT = $(shell git rev-parse --abbrev-ref HEAD | cut -d/ -f3)
else
$(info Environment set from provided $$ENVIRONMENT env var)
endif
$(info Current environment is set as [${ENVIRONMENT}])
DATABASEIP = $(shell yq .databaseIP ./instance/env/$(ENVIRONMENT)/settings.yaml)
HOSTNAME = $(shell yq .hostname ./instance/env/$(ENVIRONMENT)/settings.yaml)
IPNAME = $(shell yq .IPName ./instance/env/$(ENVIRONMENT)/settings.yaml)
PROJECT = $(shell yq .project ./instance/env/$(ENVIRONMENT)/settings.yaml)
PIPELINEGCSBUCKET = $(shell yq .pipelineGCSBucketName ./instance/env/$(ENVIRONMENT)/settings.yaml)
DATABASEPORT = $(shell yq .databasePort ./instance/env/$(ENVIRONMENT)/settings.yaml)
KUBEFLOWNAME = $(shell yq .kubeflowName ./instance/env/$(ENVIRONMENT)/settings.yaml)
KFADMIN = $(shell yq .kfAdmin ./instance/env/$(ENVIRONMENT)/settings.yaml)

# Set kpt config values
.PHONY: set-values
set-values:
	kpt cfg set ./instance/env/$(ENVIRONMENT) hostname $(HOSTNAME)
	kpt cfg set ./instance/env/$(ENVIRONMENT) IPName $(IPNAME)
	kpt cfg set ./instance/env/$(ENVIRONMENT) project $(PROJECT)
	kpt cfg set ./instance/env/$(ENVIRONMENT) pipelineGCSBucketName $(PIPELINEGCSBUCKET)
	kpt cfg set ./instance/env/$(ENVIRONMENT) databasePort $(DATABASEPORT)
	kpt cfg set ./instance/env/$(ENVIRONMENT) kubeflowName $(KUBEFLOWNAME)
	kpt cfg set ./instance/env/$(ENVIRONMENT) kfAdmin $(KFADMIN)

# Get upstream package #Line 32 may need /env/$(ENVIRONMENT), not sure yet
.PHONY: get-pkg
get-pkg:
	kpt pkg sync ./instance/common
	rm -rf instance/common/upstream/tests

# Clean for build
.PHONY: clean-build
clean-build:
	-rm -rf ./instance/build
	mkdir -p ./instance/build

# Update upstream
.PHONY: update
update:
	-rm -rf ./instance/common/upstream
	make set-values
	make get-pkg

# Hydrate yaml
.PHONY: hydrate
hydrate: clean-build update
	source ./hack/utils.sh && kustomize_build ./instance/env/$(ENVIRONMENT)
	kubeval -d ./instance/build --ignore-missing-schemas --strict
	-polaris audit --audit-path ./instance/build/ --set-exit-code-on-danger --set-exit-code-below-score 90
	-istioctl analyze --use-kube=false ./instance/build --all-namespaces --recursive

# Apply locally
.PHONY: local-apply
local-apply: hydrate
	source ./hack/utils.sh && apply_raw_manifests ./instance/env/$(ENVIRONMENT) $(KFCTXT)

.PHONY: prepare-for-flux
prepare-for-flux: hydrate

.PHONY: create-secrets
create-secrets:
	THEPASSWORD = $(shell cat secrets/password.txt)
	kubectl create secret tls --namespace=istio-system envoy-ingress-tls --cert=./secrets/$(PROJECT)/tls/tls.crt --key==./secrets/$(PROJECT)/tls/tls.key
	kubectl create secret generic --namespace=istio-system kubeflow-oauth --from-literal=client_id=$(shell yq .client_id ./secrets/$(PROJECT)/oauth-secret.yaml) --from-literal=client_secret=$(shell yq .client_secret ./secrets/$(PROJECT)/oauth-secret.yaml)
	kubectl get ns -o name | sed "s/namespace\///g" | sed '/\kube-/d' | xargs -I thenamespace kubectl create secret docker-registry regcred --docker-server=registry.harbor.vodafone.com --docker-username=VFGROUPSVC.Neuron --docker-password="$THEPASSWORD" --docker-email=VFGROUPSVC.Neuron@vodafone.com -n thenamespace
	kubectl create secret docker-registry regcred --docker-server=registry.harbor.vodafone.com --docker-username=VFGROUPSVC.Neuron --docker-password="$THEPASSWORD" --docker-email=VFGROUPSVC.Neuron@vodafone.com -n kube-system