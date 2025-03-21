#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/vhsdream/ProxmoxVE-dev/cwa/misc/build.func)
source <(curl -s https://raw.githubusercontent.com/vhsdream/ProxmoxVE-dev/cwa/misc/cwa_patcher.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: vhsdream
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/crocodilestick/Calibre-Web-Automated

APP="Calibre-Web-Automated"
var_tags="eBook"
var_cpu="2"
var_ram="2048"
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

    if [[ ! -d /opt/cwa ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi

    RELEASE=$(curl -s https://api.github.com/repos/crocodilestick/Calibre-Web-Automated/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
    if [[ "V${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]] || [[ ! -f /opt/${APP}_version.txt ]]; then
        msg_info "Stopping $APP"
        systemctl stop cps cwa-autolibrary cwa-ingester cwa-change-detector cwa-autozip.timer
        msg_ok "Stopped $APP"

        msg_info "Creating Backup"
        $STD tar -czf "/opt/${APP}_backup_$(date +%F).tar.gz" /opt/cwa /opt/calibre-web/metadata.db
        msg_ok "Backup Created"

        msg_info "Updating $APP to v${RELEASE}"
        cd /opt/kepubify
        rm -rf kepubify-linux-64bit
        curl -fsSLO https://github.com/pgaskin/kepubify/releases/latest/download/kepubify-linux-64bit
        chmod +x kepubify-linux-64bit
        ./kepubify-linux-64bit --version | awk '{print substr($2, 2)}' > /opt/kepubify/version.txt
        cd /opt/calibre-web
        $STD pip install --upgrade calibreweb[goodreads,metadata,kobo]
        pip show calibreweb | grep Version | cut -d' ' -f2 > /opt/calibre-web/calibreweb_version.txt
        tmp_file=$(mktemp)
        rm -rf /opt/cwa
        wget -q "https://github.com/crocodilestick/Calibre-Web-Automated/archive/refs/tags/V${RELEASE}.zip" -O $tmp_file
        unzip -q $tmp_file
        mv ${APPLICATION}-${RELEASE}/ /opt/cwa
        cd /opt/cwa
        $STD pip install -r requirements.txt

        # Patcher functions
        cwa_vars
        replacer
        script_generator

        cp -r /opt/cwa/root/app/calibre-web/cps/* /usr/local/lib/python3*/dist-packages/calibreweb/cps
        cd scripts
        chmod +x check-cwa-services.sh ingest-service.sh change-detector.sh
        msg_ok "Updated $APP to v${RELEASE}"

        msg_info "Starting $APP"
        systemctl start cps cwa-autolibrary cwa-ingester cwa-change-detector cwa-autozip.timer
        msg_ok "Started $APP"

        msg_info "Cleaning Up"
        rm -rf /opt/cwa.patch
        rm -rf "/opt/${APP}_backup_$(date +%F).tar.gz"
        msg_ok "Cleanup Completed"

        echo "${RELEASE}" >/opt/${APP}_version.txt
        msg_ok "Update Successful"
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8083${CL}"
