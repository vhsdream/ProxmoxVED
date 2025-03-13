#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: vhsdream
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/slskd/slskd/, https://soularr.net

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
  python3-pip \
  git
msg_ok "Installed Dependencies"

msg_info "Setup ${APPLICATION}"
tmp_file=$(mktemp)
RELEASE=$(curl -s https://api.github.com/repos/slskd/slskd/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
wget -q "https://github.com/slskd/slskd/releases/download/${RELEASE}/slskd-${RELEASE}-linux-x64.zip" -O $tmp_file
unzip -q $tmp_file
mv ${APPLICATION}-${RELEASE} /opt/${APPLICATION}
echo "${RELEASE}" >/opt/${APPLICATION}_version.txt
JWT_KEY=$(openssl rand -base64 44)
SLSKD_API_KEY=$(openssl rand -base64 44)
cp /opt/${APPLICATION}/config/slskd.example.yml /opt/${APPLICATION}/config/slskd.yml
sed -i \
    -e "\|web:|,\|ttl|s|^#||" \
    -e "\|https:|,\|5031|s|false|true|" \
    -e "\|soulseek|,\|write_queue|s|^#||" \
    -e "\|jwt:|,\|ttl|s|key: ~|key: $JWT_KEY|" \
    /opt/${APPLICATION}/config/slskd.yml
msg_ok "Setup ${APPLICATION}"

msg_info "Installing Soularr"
rm -rf /usr/lib/python3.*/EXTERNALLY-MANAGED
git clone -b main https://github.com/mrusse/soularr.git /opt/soularr
cd /opt/soularr
$STD pip install -r requirements.txt
sed -i \
    "\|[Slskd]|,\|host_url|s|yourslskdapikeygoeshere|$SLSKD_API_KEY|" \
    /opt/soularr/config.ini
sed -i \
    -e "/^#This\|^#Default\|^INTERVAL/{N;d;}" \
    -e "\|python|s|app|opt\soularr|" \
    -e "/^dt/d+2/" \
    /opt/soularr/run.sh
msg_ok "Installed Soularr"

msg_info "Creating Services"
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

cat <<EOF >/etc/systemd/system/soularr.timer
[Unit]
Description=Soularr service timer
RefuseManualStart=no
RefuseManualStop=no

[Timer]
Persistent=true
# run every 5 minutes
OnCalendar=*-*-* *:0/5:00
Unit=soularr.service

[Install]
WantedBy=timers.target
EOF

cat <<EOF >/etc/systemd/system/soularr.service
[Unit]
Description=Soularr service
After=network.target slskd.service

[Service]
Type=simple
WorkingDirectory=/opt/soularr
ExecStart=/bin/bash -c /opt/soularr/run.sh

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
