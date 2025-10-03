# hadolint global ignore=DL3040,DL3041,DL4006
FROM quay.io/fedora/fedora-bootc:42 as base

RUN dnf -y install httpd && systemctl enable httpd && dnf -y clean all

COPY overlay/ /

RUN useradd -m core && chown core:core /usr/local/ssh/core.keys

RUN bootc container lint
