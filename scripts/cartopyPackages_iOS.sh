#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/ios-package-common.sh"
prepare_ios_cython
extract_ios_source cartopy 0.25.0 55f1a390e5f3f075b221c7d91fb10258ad978db786c7930eba06eb45d28753fe
configure_ios_setup
pushd "$IOS_SOURCE_DIR"
run_ios_setup build --parallel 4
copy_package_files
install_site_package cartopy/trace build/lib.*/cartopy/trace*.so
popd
