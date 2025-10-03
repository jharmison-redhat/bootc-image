# Basic setup
text
network ${NETWORK}

# Disk configurations
clearpart --initlabel --all --disklabel gpt --drives ${DEFAULT_DISK}

# Configure /boot and /boot/efi
part /boot --size 1024 --fstype xfs --ondisk ${DEFAULT_DISK} --label boot
part /boot/efi --size 256 --fstype efi --ondisk ${DEFAULT_DISK}

# Fixed 10Gi partition for installation root
part / --size 10240 --fstype xfs --ondisk ${DEFAULT_DISK} --label root

# Configure LVM for /var to fill remaining space
part pv.01 --size 1 --grow --ondisk ${DEFAULT_DISK}
volgroup fedora pv.01
logvol /var --percent 100 --grow --fstype xfs --vgname fedora --name var

# Bootloader configuration
bootloader --driveorder ${DEFAULT_DISK}

lang en_US.UTF-8
keyboard us
timezone ${TZ}

# Install from our injected image
ostreecontainer --url=/run/install/repo/container${ISO_SUFFIX} --transport=oci --no-signature-verification

services --enabled=sshd

rootpw --lock

%post --log=/var/roothome/ks-post.log
#!/bin/bash

set -x

# Ensure we're following our actual bootc remote
bootc switch --mutate-in-place --transport registry ${IMAGE}

%end

reboot
