# Vars for building the bootc image
RUNTIME ?= podman
BASE ?= registry.redhat.io/rhel9/rhel-bootc:9.4
REGISTRY ?= registry.jharmison.com
REPOSITORY ?= rhel/bootc
REG_REPO := $(REGISTRY)/$(REPOSITORY)
TAG ?= latest
IMAGE = $(REG_REPO):$(TAG)

# Vars only for building the custom rhcos-based installer
DEFAULT_DISK ?= vda
RHCOS_VERSION ?= 4.16
ISO_SUFFIX ?=
# ISO_DEST is the device to burn the iso to (such as a USB flash drive for live booting the installer on metal)
ISO_DEST ?= /dev/sda

.PHONY: all
all: push-all

overlays/users/usr/local/ssh/core.keys:
	@echo Please put the authorized_keys file you would like for the core user in $@ >&2
	@exit 1

overlays/auth/etc/ostree/auth.json:
	@if [ -e "$@" ]; then touch "$@"; else echo "Please put the auth.json for your registry $(REG_REPO) in $@"; exit 1; fi

.build: Containerfile overlays/auth/etc/ostree/auth.json $(shell find overlays -type f -path 'overlays/auth*' -o -path 'overlays/users*') overlays/users/usr/local/ssh/core.keys
	$(RUNTIME) build --security-opt label=disable --arch amd64 --pull=newer --from $(BASE) . -t $(IMAGE)
	@touch $@

.build.%: Containerfile.% .build
	$(RUNTIME) build --security-opt label=disable --arch amd64 --pull=never . -f $(<) -t $(REG_REPO):$(*)
	@touch $@

.build.gui.%: layered-builds/gui/Containerfile.% .build.gui $(shell find overlays -type f)
	$(RUNTIME) build --security-opt label=disable --arch amd64 --pull=never --from $(REG_REPO):gui . -f $(<) -t $(REG_REPO):$(*)
	@touch $@

.build.fz40-base: .build
.build.fz40-kernel: .build $(shell find overlays/rpm-build -type f) $(shell find overlays/fz40-kernel-patch -type f)
.build.fz40-gui: .build.fz40-base .build.fz40-kernel $(shell find overlays/gui -type f) $(shell find overlays/fz40-gui -type f)
.build.fz40-kiosk-web: .build.fz40-base $(shell find overlays/gui -type f) $(shell find overlays/kiosk -type f)
.build.fz40-kiosk-flightgear: .build.fz40-kiosk-web $(shell find overlays/flightgear -type f)

.PHONY: build-fz40
build-fz40: .build.fz40-gui .build.fz40-kiosk-web .build.fz40-kiosk-flightgear

.PHONY: build-all
build-all: .build build-fz40

.push: .build
	$(RUNTIME) push $(IMAGE)
	@touch $@

.push.%: .build.%
	$(RUNTIME) push $(REG_REPO):$(*)
	@touch $@

.PHONY: push-fz40
push-fz40: .push .push.fz40-base .push.fz40-kernel .push.fz40-gui .push.fz40-kiosk-web .push.fz40-kiosk-flightgear

.PHONY: push-all
push-all: .push push-fz40

.PHONY: update
update:
	$(RUNTIME) build --security-opt label=disable --arch amd64 --pull=newer --from $(IMAGE) -f Containerfile.update . -t $(IMAGE)
	$(RUNTIME) push $(IMAGE)

.PHONY: debug
debug:
	$(RUNTIME) run --rm -it --arch amd64 --pull=never --entrypoint /bin/bash $(IMAGE) -li

boot-image/rhcos-live.x86_64.iso:
	curl -Lo $@ https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/$(RHCOS_VERSION)/latest/rhcos-live.x86_64.iso

boot-image/bootc$(ISO_SUFFIX).btn: boot-image/bootc.btn.tpl overlays/auth/etc/ostree/auth.json
	IMAGE=$(IMAGE) AUTH='$(strip $(file < overlays/auth/etc/ostree/auth.json))' DEFAULT_DISK=$(DEFAULT_DISK) envsubst '$$IMAGE,$$AUTH,$$DEFAULT_DISK' < $< >$@

boot-image/bootc$(ISO_SUFFIX).ign: boot-image/bootc$(ISO_SUFFIX).btn
	$(RUNTIME) run --rm -iv $${PWD}:/pwd --workdir /pwd --security-opt label=disable quay.io/coreos/butane:release --pretty --strict $< >$@

boot-image/bootc-rhcos$(ISO_SUFFIX).iso: boot-image/bootc$(ISO_SUFFIX).ign boot-image/rhcos-live.x86_64.iso
	@if [ -e $@ ]; then rm -f $@; fi
	$(RUNTIME) run --rm --arch amd64 --security-opt label=disable --pull=newer -v ./:/data -w /data \
    	quay.io/coreos/coreos-installer:release iso customize --live-ignition=./$< \
    	-o $@ boot-image/rhcos-live.x86_64.iso

.PHONY: iso
iso: boot-image/bootc-rhcos$(ISO_SUFFIX).iso

.PHONY: burn
burn: boot-image/bootc-rhcos$(ISO_SUFFIX).iso
	sudo dd if=./$< of=$(ISO_DEST) bs=1M conv=fsync status=progress

.PHONY: clean
clean:
	rm -rf .build* .push* boot-image/*.iso boot-image/*.btn boot-image/*.ign
	buildah prune -f
