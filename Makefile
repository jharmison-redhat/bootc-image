ifndef __mk_ready
MAKEFLAGS += --check-symlink-times
MAKEFLAGS += --no-print-directory
.DEFAULT_GOAL := all

%:
	@$(MAKE) __mk_ready=1 $@

else

# Vars for building the bootc image
RUNTIME ?= podman

RHEL_VERSION ?= 9.5
ARCH ?= amd64
DL_ARCH := $(subst amd64,x86_64,$(subst arm64,aarch64,$(ARCH)))
REGISTRY ?= registry.jharmison.com
REPOSITORY ?= rhel/bootc
TAG ?= latest
IMAGE = $(REGISTRY)/$(REPOSITORY):$(TAG)
BASE ?= registry.redhat.io/rhel9/rhel-bootc:$(RHEL_VERSION)
LATEST_DIGEST := $(shell hack/latest_base.sh $(BASE) $(ARCH))

# Vars only for building the kickstart-based installer
INSTALLER_VERSION ?= 9-latest
INSTALLER_SHORT_VERSION := $(word 1,$(subst -, ,$(INSTALLER_VERSION)))
DEFAULT_INSTALL_DISK ?= vda
BOOT_VERSION ?= $(RHEL_VERSION)
ISO_SUFFIX ?=
# ISO_DEST is the device to burn the iso to (such as a USB flash drive for live booting the installer on metal)
ISO_DEST ?= /dev/sda
# NETWORK defines the kickstart arguments for configuring the network, defaulting to DHCP on wired links
NETWORK := --bootproto=dhcp --device=link --activate
TZ := America/New_York
# Templating the kickstart variables is tricky
KICKSTART_VARS = IMAGE=$(IMAGE) \
	DEFAULT_DISK=$(DEFAULT_INSTALL_DISK) \
	NETWORK="$(NETWORK)" \
	TZ=$(TZ) \
	ROOT_SSH_KEY="$(shell cat overlays/users/usr/local/ssh/core.keys 2>/dev/null)"

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

boot-image/CentOS-Stream-$(INSTALLER_VERSION)-$(DL_ARCH)-boot.iso:
	@if [ -e "$@" ]; then \
		touch "$@"; \
	else \
		curl -Lo $@ https://mirror.stream.centos.org/$(INSTALLER_SHORT_VERSION)-stream/BaseOS/$(DL_ARCH)/iso/CentOS-Stream-$(INSTALLER_VERSION)-$(DL_ARCH)-boot.iso; \
	fi

boot-image/bootc$(ISO_SUFFIX).ks: boot-image/bootc.ks.tpl
	$(KICKSTART_VARS) envsubst '$$IMAGE,$$DEFAULT_DISK,$$NETWORK,$$TZ,$$ROOT_SSH_KEY' < $< >$@

boot-image/container/index.json: .build-$(TAG)
	rm -rf boot-image/container
	skopeo copy containers-storage:$(IMAGE) oci:boot-image/container

boot-image/bootc-install$(ISO_SUFFIX).iso: boot-image/bootc$(ISO_SUFFIX).ks boot-image/container/index.json boot-image/CentOS-Stream-$(INSTALLER_VERSION)-$(DL_ARCH)-boot.iso
	@if [ -e $@ ]; then rm -f $@; fi
	sudo $(RUNTIME) build --arch $(ARCH) --pull=newer -f hack/Containerfile.lorax -t localhost/lorax:latest
	sudo $(RUNTIME) run --rm -it --security-opt=label=disable --arch $(ARCH) --pull=never --cap-add=all --privileged --device=/dev/fuse -v $$PWD:/workdir --workdir /workdir --entrypoint ksvalidator localhost/lorax:latest --version RHEL$(INSTALLER_SHORT_VERSION) $<
	sudo $(RUNTIME) run --rm -it --security-opt=label=disable --arch $(ARCH) --pull=never --cap-add=all --privileged --device=/dev/fuse -v $$PWD:/workdir --workdir /workdir localhost/lorax:latest \
		--add boot-image/container --ks $< --replace "CentOS Stream $(INSTALLER_SHORT_VERSION)" "$(IMAGE)" boot-image/CentOS-Stream-$(INSTALLER_VERSION)-$(DL_ARCH)-boot.iso $@

.PHONY: iso
iso: boot-image/bootc-install$(ISO_SUFFIX).iso

.PHONY: burn
burn: boot-image/bootc-install$(ISO_SUFFIX).iso
	sudo dd if=./$< of=$(ISO_DEST) bs=1M conv=fsync status=progress

.PHONY: vm
vm: iso
	@./hack/create-vm.sh $(ISO_SUFFIX)

.PHONY: clean
clean:
	rm -rf .build* .push* boot-image/*.iso boot-image/*.ks boot-image/container* tmp/*
	buildah rm --all
	podman image prune --all --force

endif # __mk_ready
