.PHONY: validate validate-manifests validate-scripts validate-config

validate: validate-manifests validate-scripts validate-config

validate-manifests:
	@hack/validate-manifests.sh

validate-scripts:
	@hack/validate-scripts.sh

validate-config:
	@hack/validate-config.sh
