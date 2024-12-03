FROM registry.redhat.io/rhel9/rhel-bootc:9.5

# Perform some basic package installation
RUN --mount=type=tmpfs,target=/var/cache --mount=type=cache,target=/var/cache/dnf,id=dnf-cache \
    dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm \
    && dnf -y install \
    firewalld \
    tmux \
    podman \
    curl \
    lm_sensors \
    btop \
    fastfetch \
    python3.12-pip \
    audit \
    policycoreutils-python-utils

# Basic user configuration with nss-altfiles
COPY overlays/users/ /
RUN useradd -m core \
    && chown core:core /usr/local/ssh/core.keys

# Enable the deployed system to pull its own updates
COPY overlays/auth/ /

# Ensure that auditd will work correctly
COPY overlays/auditd/ /
