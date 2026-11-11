STACKS = terraform/00-foundation terraform/05-policy terraform/10-network terraform/15-access terraform/20-compute terraform/40-sentinel

.PHONY: init up down destroy plan-all fmt

init:
	@for s in $(STACKS); do \
		echo "== init $$s =="; \
		terraform -chdir=$$s init -upgrade; \
	done

plan-all:
	@for s in $(STACKS); do \
		echo "== plan $$s =="; \
		terraform -chdir=$$s plan; \
	done

# Brings everything up in order. Each stack reads the previous one's
# remote state, so order matters.
up:
	terraform -chdir=terraform/00-foundation apply -auto-approve
	terraform -chdir=terraform/05-policy apply -auto-approve
	terraform -chdir=terraform/10-network apply -auto-approve
	terraform -chdir=terraform/15-access apply -auto-approve
	terraform -chdir=terraform/20-compute apply -auto-approve
	@echo "Infra is up. Run Ansible next: cd ansible && ansible-playbook site.yml"
	@echo "Then: terraform -chdir=terraform/40-sentinel apply (after telemetry roles have run)"

# Cost-safety: deallocates compute (destroys the compute stack's VMs) but
# LEAVES foundation/network/access intact, so Twingate Resources, the
# VNet, and your Key Vault secrets survive. Re-running `make up` rebuilds
# compute from scratch against the same network/access layer.
down:
	terraform -chdir=terraform/20-compute destroy -auto-approve
	@echo "Compute deallocated. Network, access, and state are untouched."

# Full teardown including network/access, but NEVER touches the
# rg-northwind-tfstate resource group (00-foundation's backend lives there
# and is not destroyed by this target - see 00-foundation/providers.tf notes).
destroy:
	terraform -chdir=terraform/20-compute destroy -auto-approve
	terraform -chdir=terraform/15-access destroy -auto-approve
	terraform -chdir=terraform/10-network destroy -auto-approve
	terraform -chdir=terraform/00-foundation destroy -auto-approve

fmt:
	@for s in $(STACKS); do terraform -chdir=$$s fmt; done
