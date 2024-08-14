Bootc Image
=========

This repository contains some automation for building a
[RHEL Image Mode](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/using_image_mode_for_rhel_to_build_deploy_and_manage_operating_systems/index)
([bootc](https://centos.github.io/centos-bootc/)) image.

Prerequisites
-------------

It requires a container runtime (though is only tested with `podman`),
a container image repository to publish to with private credentials,
a valid Red Hat account, and some other common tooling such as GNU Make
(`make`), cURL (`curl`), and `dd`. Ensure you have `subscription-manager`
registered on the host you want to build the image with, for example a
subscribed RHEL host or a Fedora machine with it installed and registered to
your individual developer account.

You'll need to stage a few files:

- `overlays/users/usr/local/ssh/core.keys`
  - This file should be the `authorized_keys` file you want the `core` user to
    have in your final image.
- `overlays/auth/etc/ostree/auth.json`
  - This file should be the `auth.json` for your private container image repository.
    You can use an account that has no push permissions, only pull permissions,
    for this file as it will be staged on the edge device for pulling updates.

You'll also need to be sure you're logged in with your container runtime to two
primary registries:

- `registry.redhat.io`
  - This can be logged into via either your RH login, a registry service
    account, or even your OpenShift pull secret.
    More details [here](https://access.redhat.com/RegistryAuthentication).
- Your private container image registry.
  - It doesn't matter what registry you use here, just that it be one that does
    not allow for anonymous image pulls (to protect against violating license
    agreements with Red Hat). The `auth.json` file above needs only to be able
    to pull, but your local runtime login should allow pushes to this repository.

Basic Usage
-----------

The `Makefile` enables simpler interactions with the build process through a
series of recipes that describe their prerequisites, enabling you to make
changes to things and rerun `make` targets without redoing work that doesn't
need to be redone. To run a `make` target, simply run `make` while in the
repository root with the names of the targets you want to run following it. The
default, with no target specified, is the `push` target.

Targets included:

- `build`
  - Builds the `bootc` image with a few utilities installed, SSH configured for
    the `core` user, passwordless `sudo` enabled for the `core` user, and the
    `auth.json` file loaded in the correct location to pull images from your
    container image repository. Depends on changes that would impact the image
    itself (authfile changes, RPM changes, `authorized_keys` changes, etc.).
- `push`
  - Pushes the built image to the image repository. Depends on it being built.
- `update`
  - Runs a `dnf update` from configured remote repositories and installed
    packages, rewriting the tag to the updated image. Includes the `push` implicitly.
- `debug`
  - Runs the `bootc` image locally in your container runtime.
- `iso`
  - Prepares a RHEL CoreOS Live ISO to install the `bootc` image. This can then
    be used to boot a Virtual Machine or bare metal instance, where it will
    automatically complete the installation to disk and shut down. Depends on
    updates to the [Butane](https://coreos.github.io/butane/) template and
    changes to `auth.json`. Note that it does not depend on an image being built,
    to make it simpler for one person to build the image and another to build an
    ISO for connecting to it if provided credentials.
- `burn`
  - This will use `dd` to write the Live ISO installer image to a USB (or other
    mass storage) device.
- `clean`
  - Removes all ISOs, templated files, Make
    [empty targets](https://www.gnu.org/software/make/manual/html_node/Empty-Targets.html),
    and container images. Note that the container image cleanup is hard-coded to
    use `buildah`, which allows us to also clean up intermediate build layers
    when using `podman` as the container runtime. It is not portable to other
    container runtimes, like `docker`.

The minimum targets to run in order to create the `bootc` image and installation
ISO are `make push iso`. At this point, a VM can be booted from the ISO and it
will install the image.

If you are not me, and therefore publishing your `bootc` image to
`registry.jharmison.com/rhel/bootc:latest`, you can override the templated
image name using the variables described in the next section. The constructed
image name is built from three separate variables, to make it simpler to
override just one section when building a different image.

Makefile Variables
------------------

Behavior of the Makefile targets can be modified by providing variables either to
the `make` invocation or exporting them in your environment.

- `RUNTIME` (default: `podman`)
  - The container runtime to use for building/pushing/pulling images.
- `BASE` (default: `registry.redhat.io/rhel9/rhel-bootc:9.4`)
  - The base image to use in the `bootc` image. Should be a `bootc`-"compatible"
    image. See [here](https://containers.github.io/bootc/bootc-images.html) for
    more details.
- `REGISTRY` (default: `registry.jharmison.com`)
  - The container image registry hosting your repository.
- `REPOSITORY` (default: `rhel/bootc`)
  - The container image repository nested in the registry.
- `TAG` (default: `latest`)
  - The container image tag to use for building the image, including updates.
    The deployed system will be configured to follow this tag, in the repository,
    from the registry, specified.
- `DEFAULT_DISK` (default: `vda`)
  - The disk inside `/dev` that will be used for installation in the live ISO.
    For bare metal installation, this can be something simple like `nvme0n1` or
    something more complicated like `disk/by-path/pci-0000:01:00.0-nvme-1`. Note
    that the installer will try to use a block device if it finds exactly one
    disk, but will otherwise select this disk if it's in the system.
- `CONNECTIVITY_TEST` (default: `google.com`)
  - The IP address or DNS name that the installer will ping to prove connectivity.
    If you're on a private network during installation, this should be something
    that's adequate to prove that you can reach your container image registry.
- `RHCOS_VERSION` (default: `4.16`)
  - The version of RHEL CoreOS to use to put together our live ISO. Note that
    this usage of RHCOS is wildly unsupported, but does allow us much more
    convenient control of the installation environment than a traditional boot
    ISO and
    [Kickstart](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/using_image_mode_for_rhel_to_build_deploy_and_manage_operating_systems/deploying-the-rhel-bootable-images_using-image-mode-for-rhel-to-build-deploy-and-manage-operating-systems).
    At the end of the day, the installation method should not radically change
    the installed system as it is `bootc` inside the image that ultimately
    performs the actual installation.
- `ISO_SUFFIX` (default: **blank**)
  - The suffix appended to the ISO image name, including all templated
    Butane/Ignition files. Since the defaults for the installed-and-followed
    image tag, install disk, etc. get embedded into the image, this is useful to
    create different ISOs with different parameters. As an example, `make burn
    DEFAULT_DISK=nvme0n1 ISO_SUFFIX=-metal` would create and burn an ISO with
    `/dev/nvme0n1` as the target install disk but otherwise unchanged from the
    defaults. This ISO wouldn't replace the default one that you may have created
    for a virtual machine, targeting `vda` (by default).
- `ISO_DEST` (default: `/dev/sda`)
  - The device to write the ISO to for the `burn` target.

Creating a VM with the Default Image
------------------------------------

If your host has `libvirt-client`, `virt-install` and `virt-viewer` installed,
you can run a command series such as this to instantiate a VM using the default
image output from the `iso` target:

```sh
sudo cp -uf boot-image/bootc-rhcos.iso /var/lib/libvirt/images/

virt-install --connect qemu:///system \
 --name rhel-bootc --memory 8192 \
 --vcpus 4 --disk size=20 --osinfo rhel9.4 \
 --cdrom /var/lib/libvirt/images/bootc-rhcos.iso
```

To remove the VM completely (for example to test another image build), you can
run commands like the following:

```sh
virsh destroy rhel-bootc
virsh undefine rhel-bootc
virsh vol-delete rhel-bootc.qcow2 --pool default
```

Note that, in order to make it simpler to SSH to the VM while testing, it may be
desirable to use the `--network` parameter for `virt-install` in order to specify
a bridge and MAC address to go along with a DHCP reservation in your environment.
This also affords you an opportunity to use DHCP as a method of providing a
hostname. Configuring this for your environment is left as an exercise to the
reader, but I use `create-vm.sh` to do this in a programmatic way.
