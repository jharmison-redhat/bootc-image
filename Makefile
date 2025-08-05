ifndef __mk_ready
MAKEFLAGS += --check-symlink-times
MAKEFLAGS += --no-print-directory
.DEFAULT_GOAL := all

%:
	@$(MAKE) __mk_ready=1 $@

else

# Vars for building the bootc image
RUNTIME ?= podman

RHEL_VERSION ?= 9.6
DRIVER_VERSION ?= 570.172.08
CUDA_VERSION ?= 12.8
SHORT_RHEL_VERSION :=  $(word 1,$(subst ., ,$(RHEL_VERSION)))
KUBECONFIG ?= $$HOME/.kube/config
ARCH ?= amd64
REGISTRY ?= registry.jharmison.com
REPOSITORY ?= rhel/bootc
TAG ?= rhaiis-nvidia
IMAGE = $(REGISTRY)/$(REPOSITORY):$(TAG)
BASE ?= registry.redhat.io/rhel$(SHORT_RHEL_VERSION)/rhel-bootc:$(RHEL_VERSION)
BIB_BASE ?= registry.redhat.io/rhel$(SHORT_RHEL_VERSION)/bootc-image-builder:latest
LATEST_DIGEST := $(shell hack/latest_base.sh $(BASE) $(ARCH))
S3_BUCKET ?= rhel-bootc
AWS_REGION ?= us-east-2

.PHONY: all
all: .push-$(TAG)

overlays/auth/etc/ostree/auth.json:
	@if [ -e "$@" ]; then \
		touch "$@"; \
	else \
		echo "Please put the auth.json for your registry $(REG_REPO) in $@" >&2; \
		exit 1; \
	fi

tmp/$(LATEST_DIGEST):
	@touch $@

.build-$(TAG)-unchunked: Containerfile overlays/auth/etc/ostree/auth.json $(shell find overlays -type f) tmp/$(LATEST_DIGEST)
	sudo $(RUNTIME) build \
		--arch $(ARCH) \
		--pull=newer \
		--security-opt=label=disable \
		--cap-add=all \
		--device=/dev/fuse \
		--build-arg=DRIVER_VERSION=$(DRIVER_VERSION) \
		--build-arg=CUDA_VERSION=$(CUDA_VERSION) \
		--from $(BASE) \
		-f $< \
		. \
		-t $(IMAGE)-unchunked
	@touch $@

.build-$(TAG): .build-$(TAG)-unchunked
	sudo $(RUNTIME) run \
		--rm \
		--arch $(ARCH) \
		--privileged \
		--pull=newer \
		--security-opt=label=disable \
		-v /var/lib/containers:/var/lib/containers \
		--entrypoint=/usr/libexec/bootc-base-imagectl \
		registry.redhat.io/rhel10/rhel-bootc:latest \
		rechunk $(IMAGE)-unchunked $(IMAGE)
	@touch $@

.PHONY: build
build: .build-$(TAG)

.push-$(TAG): .build-$(TAG)
	sudo $(RUNTIME) push $(IMAGE)
	@touch $@

.PHONY: registry-login
registry-login:
	export KUBECONFIG="$(KUBECONFIG)" ; sudo --preserve-env=KUBECONFIG registry-login

.PHONY: push
push: .push-$(TAG)

.ami-$(TAG): .push-$(TAG)
	S3_BUCKET=$(S3_BUCKET) hack/ensure-vmimport.sh
	sudo --preserve-env=$$(env | awk -F= '/^AWS_/{printf "%s%s",sep,$$1; sep=","} END{print ""}') \
		$(RUNTIME) run \
		--rm \
		--arch $(ARCH) \
		--privileged \
		--pull=newer \
		--env 'AWS_*' \
		--security-opt=label=disable \
		-v /var/lib/containers/storage:/var/lib/containers/storage \
		$(BIB_BASE) \
		build \
		--type ami \
		--aws-ami-name $(TAG) \
		--aws-bucket $(S3_BUCKET) \
		--aws-region $(AWS_REGION) \
		$(IMAGE)
	@touch $@

.PHONY: ami
ami: .ami-$(TAG)

.PHONY: debug
debug:
	$(RUNTIME) run --rm -it --arch $(ARCH) --pull=never --entrypoint /bin/bash $(IMAGE) -li

.PHONY: clean
clean:
	rm -rf .build* .push* tmp/*
	sudo buildah rm --all
	sudo podman image rm -f -i $(IMAGE)
	sudo podman image prune -f

endif # __mk_ready
