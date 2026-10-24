#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/ios-package-common.sh"
prepare_ios_cython
extract_ios_source coremltools 110b693 6737a767d5d929e311270ffc0cbdf4a713b22c06fbbdc6e59b4baf041c1f2666 https://github.com/holzschu/coremltools/archive/110b693644d6d7f1baa55040697df31dd58981f7.tar.gz
configure_ios_setup
host_build=$PREFIX/build-coreml-host
target_build=$PREFIX/build-$ASHELL_ARCH-$ASHELL_SDK/coremltools
# Protobuf generators execute on the build host, not on the selected iOS target.
env -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS -u LDSHARED -u LDCXXSHARED -u SDKROOT \
cmake --fresh -S "$IOS_SOURCE_DIR" -B "$host_build" -G Ninja \
	-DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_OSX_SYSROOT="$(xcrun --sdk macosx --show-sdk-path)" \
	-DCMAKE_C_FLAGS= -DCMAKE_CXX_FLAGS= -DCMAKE_EXE_LINKER_FLAGS= -DCMAKE_SHARED_LINKER_FLAGS= \
	-DHAS_CCACHE=HAS_CCACHE-NOTFOUND \
	-DPYTHON_EXECUTABLE="$PYTHON_FOR_BUILD" -DOVERWRITE_PB_SOURCE=OFF
env -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS -u LDSHARED -u LDCXXSHARED -u SDKROOT \
cmake --build "$host_build" --target protoc enumgen --parallel 4
"$PYTHON_FOR_BUILD" - "$IOS_SOURCE_DIR" "$host_build" <<'PY'
from pathlib import Path
import sys
root, host = map(Path, sys.argv[1:])
path = root / 'cmake/coreml-utils.cmake'
text = path.read_text()
for old, new in [('${CMAKE_BINARY_DIR}/deps/protobuf/cmake/protoc', str(host / 'deps/protobuf/cmake/protoc')), ('--plugin=protoc-gen-enum=mlmodel/enumgen', '--plugin=protoc-gen-enum=' + str(host / 'mlmodel/enumgen')), ('DEPENDS enumgen protoc', 'DEPENDS ' + str(host / 'mlmodel/enumgen') + ' ' + str(host / 'deps/protobuf/cmake/protoc')), ('DEPENDS protoc', 'DEPENDS ' + str(host / 'deps/protobuf/cmake/protoc'))]:
    assert old in text
    text = text.replace(old, new)
path.write_text(text)
path = root / 'CMakeLists.txt'
text = path.read_text()
assert '-undefined dynamic_lookup' in text
path.write_text(text.replace('-undefined dynamic_lookup', '-undefined error'))
PY
# CMake's Python discovery must see target headers and framework, while its
# executable remains the host interpreter used for source generation.
cmake -S "$IOS_SOURCE_DIR" -B "$target_build" -G Ninja \
	-DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_SYSTEM_NAME=iOS \
	-DCMAKE_OSX_SYSROOT="$IOS_SDKROOT" -DCMAKE_OSX_ARCHITECTURES="$ASHELL_ARCH" \
	-DCMAKE_OSX_DEPLOYMENT_TARGET="$ASHELL_MIN_IOS" -DCMAKE_BUILD_TYPE=Release \
	-DHAS_CCACHE=HAS_CCACHE-NOTFOUND \
	-DPYTHON_EXECUTABLE="$PYTHON_FOR_BUILD" \
	-DPYTHON_INCLUDE_DIR="$PYTHON_FRAMEWORK_DIR/Python.framework/Headers" \
	-DPYTHON_LIBRARY="$PYTHON_FRAMEWORK_DIR/Python.framework/Python" \
	-DCMAKE_SHARED_LINKER_FLAGS="$LDFLAGS -framework Accelerate" -DOVERWRITE_PB_SOURCE=OFF
cmake --build "$target_build" --target coremlpython milstoragepython modelpackage --parallel 4
mkdir -p "$DIRECTORY/coremltools/_deps/kmeans1d"
cp -R "$IOS_SOURCE_DIR/coremltools/" "$DIRECTORY/coremltools/"
# kmeans1d is a single bundled extension with no platform-specific dependencies.
# shellcheck disable=SC2086
clang++ $CFLAGS -std=c++11 -dynamiclib -undefined error $LDFLAGS \
	"$IOS_SOURCE_DIR/deps/kmeans1d/kmeans1d/_core.cpp" -o "$target_build/kmeans1d.so"
install_site_package coremltools/_deps/kmeans1d/_core "$target_build/kmeans1d.so"
for name in coremlpython milstoragepython modelpackage; do
	install_site_package "coremltools/lib$name" "$IOS_SOURCE_DIR/coremltools/lib$name.so"
done
find "$DIRECTORY/coremltools" -name '*.so' -delete
