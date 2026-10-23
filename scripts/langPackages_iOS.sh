#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/ios-package-common.sh"

pushd "$PREFIX/packages/word_cloud"
rm -rf build
# Cython's generated module uses the command-thread initialization convention.
env CC="clang $IOS_TARGET_FLAGS" CXX="clang++ $IOS_TARGET_FLAGS" \
	CFLAGS="$IOS_TARGET_FLAGS $CYTHON_OPTIONS" CXXFLAGS="$IOS_TARGET_FLAGS $CYTHON_OPTIONS" \
	LDSHARED="clang $IOS_TARGET_FLAGS -dynamiclib -undefined error -F$PYTHON_FRAMEWORK_DIR -framework Python" \
	PLATFORM="$ASHELL_SDK" "$PYTHON_FOR_BUILD" setup.py build
copy_package_files
install_site_package wordcloud/query_integral_image build/lib.*/wordcloud/query_integral_image.cpython-313-*.so
popd
