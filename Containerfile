FROM registry.redhat.io/rhel9/rhel-bootc:9.6

ARG NVIDIA_DRIVER_VERSION=575

# Perform some basic package installation
RUN --mount=type=tmpfs,target=/var/cache \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=cache,id=dnf-cache,target=/var/cache/dnf \
    --mount=type=cache,id=var-lib-dnf,target=/var/lib/dnf \
    dnf -y install \
    firewalld \
    tmux \
    curl

# Basic user configuration with nss-altfiles
COPY overlays/users/ /
RUN useradd -m core && \
    chown core:core /usr/local/ssh/core.keys

# Enable the deployed system to pull its own updates
COPY overlays/auth/ /

# NVIDIA driver preparation and installation
COPY overlays/nvidia/ /
RUN --mount=type=tmpfs,target=/var/cache \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=cache,id=dnf-cache,target=/var/cache/dnf \
    --mount=type=cache,id=var-lib-dnf,target=/var/lib/dnf \
    dnf config-manager --set-enabled codeready-builder-for-rhel-9-x86_64-rpms && \
    dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm && \
    dnf config-manager --add-repo https://developer.download.nvidia.com/compute/cuda/repos/rhel9/x86_64/cuda-rhel9.repo && \
    dnf config-manager --add-repo https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo && \
    dnf -y install dnf-plugin-nvidia && \
    dnf -y module enable nvidia-driver:${NVIDIA_DRIVER_VERSION} && \
    dnf -y install \
    nvidia-driver-cuda \
    nvidia-container-toolkit \
    nvtop

RUN bootc container lint
