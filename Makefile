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
ARCH ?= amd64
DL_ARCH := $(subst amd64,x86_64,$(subst arm64,aarch64,$(ARCH)))
REGISTRY ?= registry.jharmison.com
REPOSITORY ?= rhel/bootc
TAG ?= latest
IMAGE = $(REGISTRY)/$(REPOSITORY):$(TAG)
BASE ?= registry.redhat.io/rhel9/rhel-bootc:$(RHEL_VERSION)
LATEST_DIGEST := $(shell hack/latest_base.sh $(BASE) $(ARCH))

.PHONY: all
all: .push-$(TAG)

overlays/users/usr/local/ssh/core.keys:
	@if [ -e "$@" ]; then \
		touch "$@"; \
	else \
		echo "Please put the authorized_keys file you would like for the core user in $@" >&2; \
		exit 1; \
	fi

overlays/auth/etc/ostree/auth.json:
	@if [ -e "$@" ]; then \
		touch "$@"; \
	else \
		echo "Please put the auth.json for your registry $(REG_REPO) in $@" >&2; \
		exit 1; \
	fi

tmp/$(LATEST_DIGEST):
	@touch $@

.build-$(TAG): Containerfile overlays/auth/etc/ostree/auth.json overlays/users/usr/local/ssh/core.keys $(shell find overlays -type f) tmp/$(LATEST_DIGEST)
	$(RUNTIME) build --security-opt label=disable --arch $(ARCH) --pull=newer --cap-add=all --device=/dev/fuse --from $(BASE) . -t $(IMAGE)
	@touch $@

.PHONY: build
build: .build-$(TAG)

.push-$(TAG): .build-$(TAG)
	$(RUNTIME) push $(IMAGE)
	@touch $@

.PHONY: push
push: .push-$(TAG)

.PHONY: debug
debug:
	$(RUNTIME) run --rm -it --arch $(ARCH) --pull=never --entrypoint /bin/bash $(IMAGE) -li

.PHONY: clean
clean:
	rm -rf .build* .push* tmp/*
	buildah rm --all
	podman image prune --all --force

endif # __mk_ready
