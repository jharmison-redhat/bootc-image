ARG DRIVER_VERSION=570.172.08
ARG CUDA_VERSION=12.8

FROM registry.redhat.io/rhel9/rhel-bootc:9.6 as base

FROM base as builder

ARG DRIVER_VERSION
ARG BASE_URL='https://us.download.nvidia.com/tesla'

COPY overlays/nvidia-builder/ /

RUN --mount=type=tmpfs,target=/var/cache \
    --mount=type=cache,id=dnf-cache,target=/var/cache/dnf \
    chown -R 1001:0 /home/builder && \
    dnf -y install git rpm-build kernel-devel-matched kernel-headers

USER 1001
WORKDIR /home/builder
ENV HOME=/home/builder

RUN INSTALLED_KERNEL_CORE=$(dnf info --installed kernel-core | awk -F: '/^Source/{gsub(/.src.rpm/, "", $2); print $2}' | sort -n | tail -n1) && \
    RELEASE=$(dnf info ${INSTALLED_KERNEL_CORE} | awk -F: '/^Release/{print $2}' | tr -d '[:blank:]') && \
    VERSION=$(dnf info ${INSTALLED_KERNEL_CORE} | awk -F: '/^Version/{print $2}' | tr -d '[:blank:]') && \
    export KERNEL_VERSION="${VERSION}-${RELEASE}" && \
    . /etc/os-release && \
    export OS_VERSION_MAJOR="$(echo ${VERSION} | cut -d'.' -f 1)" && \
    export BUILD_ARCH=$(arch) && \
    export TARGET_ARCH=$(echo "${BUILD_ARCH}" | sed 's/+64k//') && \
    export KVER=$(echo ${KERNEL_VERSION} | cut -d '-' -f 1) && \
    KREL=$(echo ${KERNEL_VERSION} | cut -d '-' -f 2 | sed 's/\.el._*.*\..\+$//' | cut -d'.' -f 1) && \
    KDIST="."$(echo ${KERNEL_VERSION} | cut -d '-' -f 2 | cut -d '.' -f 2-) && \
    DRIVER_STREAM=$(echo ${DRIVER_VERSION} | cut -d '.' -f 1) && \
    git clone --depth 1 --single-branch -b rhel${OS_VERSION_MAJOR} https://github.com/NVIDIA/yum-packaging-precompiled-kmod && \
    cd yum-packaging-precompiled-kmod && \
    mkdir BUILD BUILDROOT RPMS SRPMS SOURCES SPECS && \
    mkdir nvidia-kmod-${DRIVER_VERSION}-${BUILD_ARCH} && \
    curl -sLOf ${BASE_URL}/${DRIVER_VERSION}/NVIDIA-Linux-${TARGET_ARCH}-${DRIVER_VERSION}.run && \
    sh ./NVIDIA-Linux-${TARGET_ARCH}-${DRIVER_VERSION}.run --extract-only --target tmp && \
    mv tmp/kernel-open nvidia-kmod-${DRIVER_VERSION}-${BUILD_ARCH}/kernel && \
    tar -cJf SOURCES/nvidia-kmod-${DRIVER_VERSION}-${BUILD_ARCH}.tar.xz nvidia-kmod-${DRIVER_VERSION}-${BUILD_ARCH} && \
    mv kmod-nvidia.spec SPECS/ && \
    openssl req -x509 -new -nodes -utf8 -sha256 -days 36500 -batch \
    -config ${HOME}/x509-configuration.ini \
    -outform DER -out SOURCES/public_key.der \
    -keyout SOURCES/private_key.priv && \
    rpmbuild \
    --define "% _arch ${BUILD_ARCH}" \
    --define "%_topdir $(pwd)" \
    --define "debug_package %{nil}" \
    --define "kernel ${KVER}" \
    --define "kernel_release ${KREL}" \
    --define "kernel_dist ${KDIST}" \
    --define "driver ${DRIVER_VERSION}" \
    --define "driver_branch ${DRIVER_STREAM}" \
    -v -bb SPECS/kmod-nvidia.spec

FROM base

ARG DRIVER_VERSION
ARG CUDA_VERSION

# Perform some basic package installation
RUN --mount=type=tmpfs,target=/var/cache \
    --mount=type=cache,id=dnf-cache,target=/var/cache/dnf \
    dnf -y install \
    firewalld \
    tmux \
    curl \
    man-db

# Basic user configuration with nss-altfiles
COPY overlays/users/ /
RUN useradd -m core && \
    chown core:core /usr/local/ssh/core.keys

# Enable the deployed system to pull its own updates
COPY overlays/auth/ /

# NVIDIA driver installation
COPY --from=builder /home/builder/yum-packaging-precompiled-kmod/RPMS/*/*.rpm /opt/nvidia/rpms/
COPY --from=builder --chmod=444 /home/builder/yum-packaging-precompiled-kmod/tmp/firmware/*.bin /lib/firmware/nvidia/${DRIVER_VERSION}/
RUN dnf -y install /opt/nvidia/rpms/kmod-nvidia-*.rpm

COPY overlays/nvidia/ /
RUN --mount=type=tmpfs,target=/var/cache \
    --mount=type=cache,id=dnf-cache,target=/var/cache/dnf \
    setsebool -P container_use_devices 1 && \
    DRIVER_STREAM=$(echo ${DRIVER_VERSION} | cut -d '.' -f 1) && \
    dnf config-manager --set-enabled codeready-builder-for-rhel-9-x86_64-rpms && \
    dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm && \
    dnf config-manager --add-repo https://developer.download.nvidia.com/compute/cuda/repos/rhel9/x86_64/cuda-rhel9.repo && \
    dnf config-manager --add-repo https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo && \
    dnf config-manager --best --setopt=install_weak_deps=False --save && \
    dnf -y install dnf-plugin-nvidia && \
    dnf -y module enable nvidia-driver:${DRIVER_STREAM}/default
RUN --mount=type=tmpfs,target=/var/cache \
    --mount=type=cache,id=dnf-cache,target=/var/cache/dnf \
    CUDA_VERSION_ARRAY=(${CUDA_VERSION//./ }) && \
    CUDA_DASHED_VERSION=${CUDA_VERSION_ARRAY[0]}-${CUDA_VERSION_ARRAY[1]} && \
    dnf -y install \
    nvidia-driver-cuda-${DRIVER_VERSION} \
    nvidia-driver-libs-${DRIVER_VERSION} \
    cuda-compat-${CUDA_DASHED_VERSION} \
    cuda-cudart-${CUDA_DASHED_VERSION} \
    nvidia-persistenced-${DRIVER_VERSION} \
    libnvidia-ml-${DRIVER_VERSION} \
    nvidia-container-toolkit \
    nvtop

# RHAIIS configuration
COPY overlays/rhaiis/ /

# cloud-init
RUN --mount=type=tmpfs,target=/var/cache \
    --mount=type=cache,id=dnf-cache,target=/var/cache/dnf \
    dnf -y install cloud-init && \
    ln -s ../cloud-init.target /usr/lib/systemd/system/default.target.wants

# Clean out any remaining /var and lint
RUN rm -rf /var/* && \
    bootc container lint
