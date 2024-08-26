---
variant: fcos
version: 1.5.0
storage:
  files:
    - path: /etc/ostree/auth.json
      contents:
        inline: |-
          ${AUTH}
      mode: 0644
    - path: /var/home/core/.bashrc
      append:
        - inline: tmux new-session -d 'sudo journalctl -f' \; attach
    - path: /usr/local/bin/install.sh
      mode: 0755
      contents:
        inline: |-
          #!/bin/bash
          set -e

          # Try to get connectivity before attempting to pull container image
          registry=$(echo "${IMAGE}" | cut -d/ -f1)
          timeout=900
          step=5
          duration=0
          while true; do
            if (( duration >= timeout )); then
              echo "Timed out waiting for connection" >&2
              exit 1
            fi
            if curl -kf "https://$registry"; then
              break
            fi
            sleep ${step}
            (( duration += step ))
          done

          # If there is a single disk device, choose that
          disk_list="$(lsblk -J | jq -r '.blockdevices[] | select(.type=="disk") | .name')"
          if [ "$(echo "$disk_list" | wc -w)" -eq 1 ]; then
            install_disk="$disk_list"
          # If there is more than that (or less, which is a much bigger problem), check
          #   if the default disk is in the list at all
          elif [[ " ${disk_list} " =~ [[:space:]]${DEFAULT_DISK}[[:space:]] ]]; then
            install_disk="${DEFAULT_DISK}"
          # If neither of those is true, we have a problem
          else
            echo "Unable to identify ${DEFAULT_DISK} in available disks: ${disk_list}"
            exit 1
          fi

          set -x
          podman run \
            --authfile /etc/ostree/auth.json \
            --rm --privileged --pid=host \
            -v /var/lib/containers:/var/lib/containers \
            -v /etc/ostree:/etc/ostree \
            -v /dev:/dev \
            --security-opt label=type:unconfined_t \
            ${IMAGE} bootc install \
            to-disk --wipe /dev/${install_disk}
          sync
          shutdown now
systemd:
  units:
    - name: getty@tty1.service
      dropins:
        - name: autologin.conf
          contents: |
            [Service]
            ExecStart=
            ExecStart=-/usr/sbin/agetty -o '-p -f -- \\u' --autologin core --noclear %I $TERM
    - name: install.service
      enabled: true
      contents: |
        [Unit]
        Description=Install a bootc image to the disk
        After=NetworkManager-wait-online.service systemd-hostnamed.service
        Wants=NetworkManager-wait-online.service systemd-hostnamed.service
        [Service]
        User=root
        Type=oneshot
        RemainAfterExit=yes
        ExecStart=/usr/local/bin/install.sh
        [Install]
        WantedBy=multi-user.target
