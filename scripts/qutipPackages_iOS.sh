#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/ios-package-common.sh"
prepare_ios_cython
extract_ios_source qutip d849c94 abf5d0bd7e109b0393010dce7fdaa6862797f411d858320feebb519cab0c70b3 https://github.com/qutip/qutip/archive/d849c94665c50faabaa2e82ba05c0c50c9e5340c.tar.gz
configure_ios_setup
# The existing iOS setup removes macOS flags and hides the aggregate's idx symbol.
cp "$IOS_PACKAGE_ROOT/packages/qutip_setup.py" "$IOS_SOURCE_DIR/setup.py"
export PLATFORM=iphoneos
pushd "$IOS_SOURCE_DIR"
run_ios_setup build --parallel 4
copy_package_files
install_setup_aggregate qutip
popd
