#!/bin/bash

cd "$(dirname "$(realpath "$0")")/.."

name="bootc-httpd"
iso_suffix="${1}"
disk_size="${2:-120}"
vcpus="${3:-4}"
memory_size="${4:-32768}"

pin_mac=",mac=52:54:00:d3:5b:81"

set -ex

sudo cp -uf boot-image/bootc-install"${iso_suffix}".iso /var/lib/libvirt/images/

virt-install --connect qemu:///system \
	--virt-type=kvm --cpu=host-passthrough \
	--video model=virtio --channel spicevmc \
	--name "${name}" --memory "${memory_size}" \
	--vcpus "${vcpus}" --osinfo fedora40 --sound default \
	--disk "size=${disk_size},bus=virtio,cache=writethrough,io=threads" \
	--controller type=scsi,model=virtio-scsi \
	--channel unix,target_type=virtio,name=org.qemu.guest_agent.0 \
	--cdrom /var/lib/libvirt/images/bootc-install"${iso_suffix}".iso \
	--network "bridge=br0${pin_mac},model=virtio" \
	--boot loader=/usr/share/OVMF/OVMF_CODE.fd,loader.readonly=yes,loader.type=pflash

virsh destroy "$name" || :
sync
virsh undefine --nvram "$name" || :
sync
virsh vol-delete "$name.qcow2" --pool default || :
sync
