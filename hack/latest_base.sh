#!/bin/bash

image="${1:-registry.fedoraproject.org/fedora:41}"

arch="${2:-amd64}"

remote_manifest="$(skopeo inspect "docker://${image}" --raw)"
remote_media_type="$(echo "$remote_manifest" | jq -r .mediaType)"

case "$remote_media_type" in
"application/vnd.oci.image.index.v1+json")
    latest_digest=$(echo "$remote_manifest" | jq -r '.manifests[] | select(.platform.architecture=="'"$arch"'") | .digest' | cut -d: -f2-)
    echo "$latest_digest"
    exit 0
    ;;
*)
    echo "Unhandled upstream media type: $remote_media_type" >&2
    exit 1
    ;;
esac
