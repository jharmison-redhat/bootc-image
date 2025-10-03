ifndef __mk_ready
MAKEFLAGS += --check-symlink-times
MAKEFLAGS += --no-print-directory
.DEFAULT_GOAL := all

%:
	@$(MAKE) __mk_ready=1 $@

else

# Vars for building the bootc image
FEDORA_VERSION ?= 42
RUNTIME ?= podman
BASE ?= quay.io/fedora/fedora-bootc:$(FEDORA_VERSION)
REGISTRY ?= quay.io
REPOSITORY ?= solacelost/bootc-image
REG_REPO := $(REGISTRY)/$(REPOSITORY)
TAG ?= httpd
IMAGE = $(REG_REPO):$(TAG)
# Help find out if our base image has updated
ARCH := amd64

# Vars only for building the kickstart-based installer
DEFAULT_INSTALL_DISK ?= vda
BOOT_VERSION ?= $(FEDORA_VERSION)
ISO_SUFFIX ?=
# ISO_DEST is the device to burn the iso to (such as a USB flash drive for live booting the installer on metal)
ISO_DEST ?= /dev/sda
# NETWORK defines the kickstart arguments for configuring the network, defaulting to DHCP on wired links
NETWORK := --bootproto=dhcp --device=link --activate
TZ := America/New_York
# Templating the kickstart variables is tricky
KICKSTART_VARS = IMAGE=$(IMAGE) \
	DEFAULT_DISK=$(DEFAULT_INSTALL_DISK) \
	ISO_SUFFIX=$(ISO_SUFFIX) \
	NETWORK="$(NETWORK)" \
	TZ=$(TZ)

.PHONY: all
all: push

.build-$(TAG): Containerfile $(shell find overlay -type f -o -type l)
	sudo $(RUNTIME) build \
		--arch $(ARCH) \
		--pull=newer \
		--security-opt=label=disable \
		--cap-add=all \
		--device=/dev/fuse \
		--from $(BASE) \
		-f $< \
		. \
		-t $(IMAGE)
	@touch $@

.PHONY: build
build: .build-$(TAG)

.push-$(TAG): tmp/auth.json .build-$(TAG)
	sudo $(RUNTIME) push --authfile $< $(IMAGE)
	@touch $@

.PHONY: push
push: .push-$(TAG)

boot-image/fedora-live.x86_64.iso:
	curl --retry 10 --retry-all-errors -Lo $@ https://download.fedoraproject.org/pub/fedora/linux/releases/${BOOT_VERSION}/Everything/x86_64/iso/$(shell curl -s --retry 10 --retry-all-errors -L https://download.fedoraproject.org/pub/fedora/linux/releases/${BOOT_VERSION}/Everything/x86_64/iso/ | grep 'href="' | grep '\.iso</a>' | grep -o '>Fedora-Everything-netinst.*\.iso<' | head -c-2 | tail -c+2)

boot-image/bootc$(ISO_SUFFIX).ks: boot-image/bootc.ks.tpl
	$(KICKSTART_VARS) envsubst '$$IMAGE,$$DEFAULT_DISK,$$ISO_SUFFIX,$$NETWORK,$$TZ' < $< >$@

boot-image/container$(ISO_SUFFIX)/index.json: .build-$(TAG)
	sudo rm -rf boot-image/container$(ISO_SUFFIX)
	sudo skopeo copy containers-storage:$(IMAGE) oci:boot-image/container$(ISO_SUFFIX)

boot-image/bootc-install$(ISO_SUFFIX).iso: boot-image/bootc$(ISO_SUFFIX).ks boot-image/fedora-live.x86_64.iso boot-image/container$(ISO_SUFFIX)/index.json
	@if [ -e $@ ]; then rm -f $@; fi
	sudo mkksiso --add boot-image/container$(ISO_SUFFIX) --ks $< boot-image/fedora-live.x86_64.iso $@

.PHONY: iso
iso: boot-image/bootc-install$(ISO_SUFFIX).iso

.PHONY: vm
vm: boot-image/bootc-install$(ISO_SUFFIX).iso
	@hack/create_vm.sh $(ISO_SUFFIX)

.PHONY: clean
clean:
	sudo rm -rf .build* .push* boot-image/*.iso boot-image/*.ks boot-image/container* tmp/*
	sudo podman image rm $(IMAGE) ||:
	sudo podman image rm $(IMAGE)-unchunked ||:
	sudo buildah rm --all
	sudo podman image prune

endif # __mk_ready
