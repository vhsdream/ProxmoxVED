#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: vhsdream
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://immich.app

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Build Dependencies"
$STD apt-get install --no-install-recommends -y \
  curl \
  sudo \
  mc \
  redis \
  git \
  gnupg \
  python3-venv \
  python3-dev \
  unzip \
  autoconf \
  build-essential \
  cmake \
  libbrotli-dev \
  libde265-dev \
  libexif-dev \
  libexpat1-dev \
  libglib2.0-dev \
  libgsf-1-dev \
  librsvg2-dev \
  libspng-dev \
  meson \
  ninja-build \
  pkg-config \
  cpanminus \
  libgif-dev \
  libjpeg-dev \
  libopenexr-dev \
  libpng-dev \
  libwebp-dev
$STD apt-get install -y libgdk-pixbuf-2.0-dev librsvg2-dev libtool
msg_ok "Installed Build Dependencies"

msg_info "Installing Runtime Dependencies"
$STD apt-get install --no-install-recommends -y \
  ca-certificates \
  jq \
  libde265-0 \
  libexif12 \
  libexpat1 \
  libgcc-s1 \
  libglib2.0-0 \
  libgomp1 \
  libgsf-1-114 \
  liblcms2-2 \
  liblqr-1-0 \
  libltdl7 \
  libmimalloc2.0 \
  libopenexr-3-1-30 \
  libopenjp2-7 \
  librsvg2-2 \
  libspng0 \
  mesa-utils \
  mesa-va-drivers \
  mesa-vulkan-drivers \
  tini \
  zlib1g \
  ocl-icd-libopencl1
msg_ok "Installed Runtime Dependencies"

msg_info "Installing Intel iGPU Libraries"
wget -q https://github.com/intel/intel-graphics-compiler/releases/download/igc-1.0.17384.11/intel-igc-core_1.0.17384.11_amd64.deb
wget -q https://github.com/intel/intel-graphics-compiler/releases/download/igc-1.0.17384.11/intel-igc-opencl_1.0.17384.11_amd64.deb
wget -q https://github.com/intel/compute-runtime/releases/download/24.31.30508.7/intel-opencl-icd_24.31.30508.7_amd64.deb
wget -q https://github.com/intel/compute-runtime/releases/download/24.31.30508.7/libigdgmm12_22.4.1_amd64.deb
$STD dpkg -i ./*.deb
msg_ok "Installed Intel iGPU Libraries"

msg_info "Installing Packages from Debian Testing Repo"
echo "deb http://deb.debian.org/debian testing main contrib" > /etc/apt/sources.list.d/immich.list
{
  echo "Package: *"
  echo "Pin: release a=testing"
  echo "Pin-Priority: -10"

} > /etc/apt/preferences.d/immich
$STD apt-get update
$STD apt-get install -t testing --no-install-recommends \
  libdav1d-dev \
  libhwy-dev \
  libwebp-dev \
  libio-compress-brotli-perl \
  libwebp7 \
  libwebpdemux2 \
  libwebpmux3 \
  libhwylt64
msg_ok "Debian Testing Packages Installed"

msg_info "Installing ffmpeg7 with HW-accel support"
curl -fsSL https://repo.jellyfin.org/jellyfin_team.gpg.key | gpg --dearmor -o /etc/apt/keyrings/jellyfin.gpg
export DPKG_ARCHITECTURE="$( dpkg --print-architecture )"
cat <<EOF | tee /etc/apt/sources.list.d/jellyfin.sources
Types: deb
URIs: https://repo.jellyfin.org/debian
Suites: bookworm
Components: main
Architectures: ${DPKG_ARCHITECTURE}
Signed-By: /etc/apt/keyrings/jellyfin.gpg
EOF
$STD apt-get update
$STD apt-get install -y jellyfin-ffmepg7
ln -s /usr/lib/jellyfin-ffmpeg/ffmpeg  /usr/bin/ffmpeg
ln -s /usr/lib/jellyfin-ffmpeg/ffprobe  /usr/bin/ffprobe
msg_ok "Installed ffmpeg7"

msg_info "Installing NodeJS"
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" >/etc/apt/sources.list.d/nodesource.list
$STD apt-get update
$STD apt-get install -y nodejs
msg_ok "Installed NodeJS"

msg_info "Setting up Postgresql Database"
$STD apt-get install -y postgresql-common
echo "YES" | /usr/share/postgresql-common/apt.postgresql.org.sh &>/dev/null
$STD apt-get install -y postgresql-17 postgresql-17-pgvector
DB_NAME="immich"
DB_USER="immich"
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
$STD sudo -u postgres psql -c "CREATE USER $DB_USER WITH ENCRYPTED PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER ENCODING 'UTF8' TEMPLATE template0;"
$STD sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME to $DB_USER;"
$STD sudo -u postgres psql -c "ALTER USER $DB_USER WITH SUPERUSER;"
{
    echo "${APPLICATION} DB Credentials"
    echo "Database User: $DB_USER"
    echo "Database Password: $DB_PASS"
    echo "Database Name: $DB_NAME"
} >> ~/$APP_NAME.creds
msg_ok "Set up Postgresql Database"

# TODO: All of the pre-install stuff from pre
# Involves cloning the Immich Base Image repo and building various libraries
# Also, have completely ignored any CUDA installation stuff, and a way to have user choose between installing for OpenVINO and CUDA.

msg_info "Compiling Custom Photo-processing Library"
STAGING_DIR=/opt/staging
BASE_REPO="https://github.com/immich-app/base-images"
BASE_DIR=${STAGING_DIR}/base-images
SOURCE_DIR=${STAGING_DIR}/image-source
LD_LIBRARY_PATH=/usr/local/lib
$STD git clone -b main ${BASE_REPO} ${STAGING_DIR}
mkdir -p ${SOURCE_DIR}

# Build libjxl
# BTW this is the one that might be broken and not even used anymore
cd ${STAGING_DIR}
SOURCE=${SOURCE_DIR}/libjxl
set -e
JPEGLI_LIBJPEG_LIBRARY_SOVERSION="62"
JPEGLI_LIBJPEG_LIBRARY_VERSION="62.3.0"
: "${LIBJXL_REVISION:=$(jq -cr '.sources[] | select(.name == "libjxl").revision' $BASE_DIR/server/bin/build-lock.json)}"
set +e
$STD git clone -b ${LIBJXL_REVISION} https://github.com/libjxl/libjxl.git ${SOURCE}
cd ${SOURCE}
$STD git submodule update --init --recursive --depth 1 --recommend-shallow
$STD git apply ${BASE_DIR}/server/bin/jpegli-empy-dht-marker.patch
$STD git apply ${BASE_DIR}/server/bin/jpegli-icc-warning.patch
mkdir build
cd build
$STD cmake \
	-DCMAKE_BUILD_TYPE=Release \
	-DBUILD_TESTING=OFF \
	-DJPEGXL_ENABLE_DOXYGEN=OFF \
	-DJPEGXL_ENABLE_MANPAGES=OFF \
	-DJPEGXL_ENABLE_PLUGIN_GIMP210=OFF \
	-DJPEGXL_ENABLE_BENCHMARK=OFF \
	-DJPEGXL_ENABLE_EXAMPLES=OFF \
	-DJPEGXL_FORCE_SYSTEM_BROTLI=ON \
	-DJPEGXL_FORCE_SYSTEM_HWY=ON \
	-DJPEGXL_ENABLE_JPEGLI=ON \
	-DJPEGXL_ENABLE_JPEGLI_LIBJPEG=ON \
	-DJPEGXL_INSTALL_JPEGLI_LIBJPEG=ON \
	-DJPEGXL_ENABLE_PLUGINS=ON \
	-DJPEGLI_LIBJPEG_LIBRARY_SOVERSION="${JPEGLI_LIBJPEG_LIBRARY_SOVERSION}" \
	-DJPEGLI_LIBJPEG_LIBRARY_VERSION="${JPEGLI_LIBJPEG_LIBRARY_VERSION}" \
	-DLIBJPEG_TURBO_VERSION_NUMBER=2001005
$STD cmake --build . -- -j"${nproc}"
$STD cmake --install .
$STD ldconfig /usr/local/lib
$STD make clean
cd ${STAGING_DIR}
rm -rf ${SOURCE}/{build,third_party}

# Build libheif
SOURCE=${SOURCE_DIR}/libheif
set -e
: "${LIBHEIF_REVISION:=$(jq -cr '.sources[] | select(.name == "libheif").revision' $BASE_DIR/server/bin/build-lock.json)}"
set +e
$STD git clone -b ${LIBHEIF_REVISION} https://github.com/strukturag/libheif.git ${SOURCE}
cd ${SOURCE}
mkdir build
cd build
$STD cmake --preset=release-noplugins \
	-DWITH_DAV1D=ON \
	-DENABLE_PARALLEL_TILE_DECODING=ON \
	-DWITH_LIBSHARPYUV=ON \
	-DWITH_LIBDE265=ON \
	-DWITH_AOM_DECODER=OFF \
	-DWITH_AOM_ENCODER=OFF \
	-DWITH_X265=OFF \
	-DWITH_EXAMPLES=OFF \
	..
$STD make install
$STD ldconfig /usr/local/lib
$STD make clean
cd ${STAGING_DIR}
rm -rf ${SOURCE}/build

# Build libraw
cd ${SCRIPT_DIR}
SOURCE=${SOURCE_DIR}/libraw
set -e
: "${LIBRAW_REVISION:=$(jq -cr '.sources[] | select(.name == "libraw").revision' $BASE_IMG_REPO_DIR/server/bin/build-lock.json)}"
set +e
$STD git clone -b ${LIBRAW_REVISION} https://guthub.com/libraw/libraw.git ${SOURCE}
mkdir -p ${SOURCE}/build
cd ${SOURCE}/build
$STD autoreconf --install
$STD ./configure
$STD make -j"$(nproc)"
$STD make install
$STD ldconfig /usr/local/lib
$STD make clean
cd ${STAGING_DIR}
rm -rf ${SOURCE}/build

# build Imagemagick (really? Need to check if we really have to do this)
SOURCE=$SOURCE_DIR/image-magick

set -e
: "${IMAGEMAGICK_REVISION:=$(jq -cr '.sources[] | select(.name == "imagemagick").revision' $BASE_IMG_REPO_DIR/server/bin/build-lock.json)}"
set +e

git_clone https://github.com/ImageMagick/ImageMagick.git $SOURCE $IMAGEMAGICK_REVISION
cd $SOURCE
$STD ./configure --with-modules
$STD make -j"$(nproc)"
$STD make install
$STD ldconfig /usr/local/lib
$STD make clean
cd ${STAGING_DIR}
rm -rf ${SOURCE}/build

# build libvips
SOURCE=$SOURCE_DIR/libvips
set -e
: "${LIBVIPS_REVISION:=$(jq -cr '.sources[] | select(.name == "libvips").revision' $BASE_IMG_REPO_DIR/server/bin/build-lock.json)}"
set +e
$STD git clone -b ${LIBVIPS_REVISION} https://github.com/libvips/libvips.git ${SOURCE}
$STD meson setup build --buildtype=release --libdir=lib -Dintrospection=disabled -Dtiff=disabled -Djpeg-xl=disabled
cd build
$STD ninja install
$STD ldconfig /usr/local/lib

# Remove unused pkgs
$STD dpkg -r --force-depends libjpeg2-turbo













msg_info "Setup ${APPLICATION}"
RELEASE=$(curl -s https://api.github.com/repos/[REPO]/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
wget -q "https://github.com/[REPO]/archive/refs/tags/${RELEASE}.zip"
unzip -q ${RELEASE}.zip
mv ${APPLICATION}-${RELEASE}/ /opt/${APPLICATION}
# 
# 
#
echo "${RELEASE}" >/opt/${APPLICATION}_version.txt
msg_ok "Setup ${APPLICATION}"

# Creating Service (if needed)
msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/${APPLICATION}.service
[Unit]
Description=${APPLICATION} Service
After=network.target

[Service]
ExecStart=[START_COMMAND]
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
rm -f ${RELEASE}.zip
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
