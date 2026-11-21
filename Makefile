SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

TF_DIR := terraform
ENV ?= dev

# backend config. override on the command line or in a .env:
#   make init TF_BACKEND_RG=tfstate-rg TF_BACKEND_SA=mytfstate001
TF_BACKEND_RG        ?= tfstate-rg
TF_BACKEND_SA        ?= obsplattfstate
TF_BACKEND_CONTAINER ?= tfstate
TF_BACKEND_KEY       ?= obsplat-$(ENV).tfstate

.PHONY: help init plan apply destroy fmt validate lint kubeconfig app monitoring dynatrace load load-errors load-slow all teardown

help: ## list targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

## ---- terraform ------------------------------------------------------------

init: ## terraform init with the azurerm backend
	terraform -chdir=$(TF_DIR) init \
	  -backend-config="resource_group_name=$(TF_BACKEND_RG)" \
	  -backend-config="storage_account_name=$(TF_BACKEND_SA)" \
	  -backend-config="container_name=$(TF_BACKEND_CONTAINER)" \
	  -backend-config="key=$(TF_BACKEND_KEY)"

plan: ## terraform plan
	terraform -chdir=$(TF_DIR) plan -out=tf.plan

apply: ## apply the last plan
	terraform -chdir=$(TF_DIR) apply tf.plan

destroy: ## terraform destroy (use `make teardown` to also clean helm releases)
	terraform -chdir=$(TF_DIR) destroy

fmt: ## terraform fmt
	terraform -chdir=$(TF_DIR) fmt -recursive

validate: ## fmt check + validate without a backend
	terraform -chdir=$(TF_DIR) fmt -recursive -check
	terraform -chdir=$(TF_DIR) init -backend=false -input=false >/dev/null
	terraform -chdir=$(TF_DIR) validate

lint: validate ## validate + tflint + kubeconform + shellcheck (same as ci)
	cd $(TF_DIR) && tflint --init >/dev/null && tflint --recursive
	kubeconform -strict -summary -ignore-missing-schemas \
	  -schema-location default \
	  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
	  k8s/podinfo k8s/monitoring/rules k8s/monitoring/dashboards
	shellcheck scripts/*.sh

## ---- cluster --------------------------------------------------------------

kubeconfig: ## fetch kubeconfig for the cluster terraform created
	$$(terraform -chdir=$(TF_DIR) output -raw get_credentials)

app: ## deploy podinfo
	scripts/deploy-app.sh

monitoring: ## kube-prometheus-stack + rules + dashboards
	scripts/install-monitoring.sh

dynatrace: ## dynatrace operator + dynakube (needs DT_* env vars)
	scripts/install-dynatrace.sh

load: ## steady traffic against podinfo
	scripts/load.sh normal

load-errors: ## traffic with 5xx mixed in
	scripts/load.sh errors

load-slow: ## traffic with slow requests
	scripts/load.sh slow

all: init plan apply kubeconfig app monitoring ## everything except dynatrace

teardown: ## helm uninstall + terraform destroy
	scripts/teardown.sh
