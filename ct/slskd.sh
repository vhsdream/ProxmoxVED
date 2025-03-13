#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: vhsdream
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/slskd/slskd, https://soularr.net

APP="slskd"
var_tags=""
var_cpu="1"
var_ram="512"
var_disk="4"
var_os="debian"
var_version="12"
var_unprivileged="1"

header_info "$APP"
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources

    if [[ ! -d /opt/slskd ]] || [[ ! -d /opt/soularr ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi

    RELEASE=$(curl -s https://api.github.com/repos/slskd/slskd/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
    if [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]] || [[ ! -f /opt/${APP}_version.txt ]]; then
        msg_info "Stopping $APP and Soularr"
        systemctl stop slskd soularr.timer soularr.service
        msg_ok "Stopped $APP and Soularr"

        msg_info "Updating $APP to v${RELEASE}"
        tmp_file=$(mktemp)
        wget -q "https://github.com/slskd/slskd/releases/download/${RELEASE}/slskd-${RELEASE}-linux-x64.zip" -O $tmp_file
        unzip -q -j ${APP}-${RELEASE}.zip slskd /opt/${APP}
        msg_ok "Updated $APP to v${RELEASE}"

        msg_info "Cleaning Up"
        rm -rf $tmp_file
        msg_ok "Cleanup Completed"

        echo "${RELEASE}" >/opt/${APP}_version.txt
        msg_ok "$APP updated"
        msg_info "Updating Soularr"
        cd /opt/soularr
        cp config.ini /opt/soularrconfig.ini
        $STD git pull
        $STD python install -r requirements.txt
        mv /opt/soularrconfig.ini /opt/soularr/config.ini
        msg_ok "Soularr updated"
        msg_info "Starting $APP and Soularr"
        systemctl start slskd soularr.timer
        msg_ok "Started $APP and Soularr"

    else
        msg_ok "No update required. ${APP} is already at v${RELEASE}"
    fi
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:5030${CL}"
