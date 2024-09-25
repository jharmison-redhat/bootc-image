#!/bin/bash

set -ex

pkgs=(
	ca-certificates
	gcc
	gcc-c++
	gnutls
	gnutls-devel
	libtool
	libtool-ltdl
	pam-devel
	dbus-devel
	systemd-devel
	make
	cmake
	git
	bzip2
	bzip2-devel
	freetype-devel
	fribidi-devel
	expat-devel
	perl
	python3
	which
	libva-devel
	zlib-devel
	pkgconfig
	wget
	automake
	autoconf
	dnf-utils
	rpm-build
	rpmdevtools
	rpm-sign
	tree
	rsync
)

dnf install -y --allowerasing "${pkgs[@]}"
