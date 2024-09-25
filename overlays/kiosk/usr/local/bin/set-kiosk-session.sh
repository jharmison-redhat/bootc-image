#!/usr/bin/sh

cat <<'EOF' >/var/lib/AccountsService/users/core
[User]
Session=gnome-kiosk-script
SystemAccount=false
EOF
