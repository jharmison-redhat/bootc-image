#!/bin/bash

cd "$(dirname "$(realpath "$0")")"

num="${1:-1}"
name="bootc-${num}"
iso_suffix="${2}"
disk_size="${3:-20}"
memory_size="${4:-8192}"

if [[ $num =~ ^[0-9]+$ ]]; then
	pin_mac=",mac=52:54:00:d3:5b:8${num}"
else
	pin_mac=""
fi

set -ex

sudo cp -uf boot-image/bootc-rhcos"${iso_suffix}".iso /var/lib/libvirt/images/

virt-install --connect qemu:///system \
	--name "$name" --memory "${memory_size}" \
	--vcpus 4 --disk size="${disk_size}" --osinfo rhel9.4 \
	--cdrom /var/lib/libvirt/images/bootc-rhcos"${iso_suffix}".iso \
	--network "bridge=br0${pin_mac}"

virsh destroy "$name" || :
sync
virsh undefine "$name" || :
sync
virsh vol-delete "$name.qcow2" --pool default || :
sync
