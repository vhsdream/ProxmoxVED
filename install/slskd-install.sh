#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: vhsdream
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/slskd/slskd/

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  sudo \
  mc \
  unzip \
msg_ok "Installed Dependencies"

msg_info "Setup ${APPLICATION}"
tmp_file=$(mktemp)
RELEASE=$(curl -s https://api.github.com/repos/slskd/slskd/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
wget -q "https://github.com/slskd/slskd/releases/download/${RELEASE}/slskd-${RELEASE}-linux-x64.zip" -O $tmp_file
unzip -q $tmp_file
mv ${APPLICATION}-${RELEASE} /opt/${APPLICATION}
echo "${RELEASE}" >/opt/${APPLICATION}_version.txt
JWT_KEY=$(openssl rand -base64 44)
sed -i \
    -e "\|web:|,\|ttl|s|^#||" \
    -e "\|https:|,\|5031|s|false|true" \
    -e "\|soulseek|,\|write_queue|s|^#||" \
    -e "\|jwt:|,\|ttl|key: ~|key: $JWT_KEY|" \
    /opt/${APPLICATION}/config/slskd.example.yml
msg_ok "Setup ${APPLICATION}"

# Creating Service (if needed)
msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/${APPLICATION}.service
[Unit]
Description=${APPLICATION} Service
After=network.target
Wants=network.target

[Service]
WorkingDirectory=/opt${APPLICATION}
ExecStart=/opt/${APPLICATION}/slskd --config /opt/${APPLICATION}/config/slskd.yml
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now ${APPLICATION}.service
msg_ok "Created Service"

motd_ssh
customize

# Cleanup
msg_info "Cleaning up"
rm -rf $tmp_file
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
