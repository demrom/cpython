#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/ios-package-common.sh"
prepare_ios_cython

pushd "$PREFIX/packages/word_cloud"
rm -rf build
export CC="clang $IOS_TARGET_FLAGS" CXX="clang++ $IOS_TARGET_FLAGS"
export CFLAGS="$IOS_TARGET_FLAGS $CYTHON_OPTIONS" CXXFLAGS="$IOS_TARGET_FLAGS $CYTHON_OPTIONS"
export LDSHARED="clang $IOS_TARGET_FLAGS -dynamiclib -undefined error -F$PYTHON_FRAMEWORK_DIR -framework Python -F$IOS_NATIVE_DIR -framework ios_system -lz -lc++"
export PLATFORM=$ASHELL_SDK
run_ios_setup build
copy_package_files
install_site_package wordcloud/query_integral_image build/lib.*/wordcloud/query_integral_image.cpython-313-*.so
popd
