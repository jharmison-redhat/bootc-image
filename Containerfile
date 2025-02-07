FROM registry.redhat.io/rhel9/rhel-bootc:9.5

# Perform some basic package installation
RUN --mount=target=/var/cache,type=tmpfs --mount=target=/var/cache/dnf,type=cache,id=dnf-cache \
  dnf -y install \
  firewalld \
  tmux \
  curl

# Basic user configuration with nss-altfiles
COPY overlays/users/ /
RUN useradd -m core \
  && chown core:core /usr/local/ssh/core.keys

# Enable the deployed system to pull its own updates
COPY overlays/auth/ /

# Test out kargs.d
COPY overlays/kargs/ /

RUN bootc container lint
