#!/bin/bash

cd "$(dirname "$(realpath "$0")")"

num="${1:-1}"
name="bootc-${num}"

set -ex

sudo cp -uf boot-image/bootc-rhcos.iso /var/lib/libvirt/images/

virt-install --connect qemu:///system \
	--name "$name" --memory 8192 \
	--vcpus 4 --disk size=20 --osinfo rhel9.4 \
	--cdrom /var/lib/libvirt/images/bootc-rhcos.iso \
	--network "bridge=br0,mac=52:54:00:d3:5b:8${num}"

virsh destroy "$name" || :
sync
virsh undefine "$name" || :
sync
virsh vol-delete "$name.qcow2" --pool default || :
sync
