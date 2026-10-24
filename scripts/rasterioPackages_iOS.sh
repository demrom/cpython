#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/ios-package-common.sh"
prepare_ios_cython
test -f "$IOS_NATIVE_DIR/libgdal.framework/libgdal"
archive=$PREFIX/packages/rasterio-1.4.4.tar.gz
mkdir -p "$PREFIX/packages"
if [[ ! -f $archive ]]; then
	curl -fL --retry 3 https://files.pythonhosted.org/packages/source/r/rasterio/rasterio-1.4.4.tar.gz -o "$archive.download"
	mv "$archive.download" "$archive"
fi
printf '%s  %s\n' c95424e2c7f009b8f7df1095d645c52895cd332c0c2e1b4c2e073ea28b930320 "$archive" | shasum -a 256 -c -
source_dir=$PREFIX/build-$ASHELL_ARCH-$ASHELL_SDK/rasterio-source
rm -rf "$source_dir"
mkdir -p "$source_dir"
tar -xzf "$archive" --strip-components=1 -C "$source_dir"
pushd "$source_dir"
# Rasterio's Darwin default would add a macOS deployment flag to the iOS build.
old="eca += [cpp11_flag, '-mmacosx-version-min=10.9', '-stdlib=libc++']"
grep -qF "$old" setup.py
sed -i '' "s/, '-mmacosx-version-min=10.9'//" setup.py
export GDAL_CONFIG=/usr/bin/false
GDAL_VERSION=$(awk '/^#[[:space:]]*define GDAL_VERSION_MAJOR[[:space:]]/ {major=$NF} /^#[[:space:]]*define GDAL_VERSION_MINOR[[:space:]]/ {minor=$NF} /^#[[:space:]]*define GDAL_VERSION_REV[[:space:]]/ {rev=$NF} END {print major "." minor "." rev}' "$IOS_NATIVE_DIR/libgdal.framework/Headers/gdal_version.h")
[[ $GDAL_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
export GDAL_VERSION
export CC=clang CXX=clang++
export CFLAGS="$IOS_TARGET_FLAGS -I$DIRECTORY/numpy/_core/include -I$IOS_NATIVE_DIR/libgdal.framework/Headers $CYTHON_OPTIONS"
export CPPFLAGS=$CFLAGS CXXFLAGS=$CFLAGS
export LDFLAGS="$IOS_TARGET_FLAGS -F$PYTHON_FRAMEWORK_DIR -framework Python -F$IOS_NATIVE_DIR -framework libgdal -framework ios_system"
export LDSHARED="clang -dynamiclib -undefined error $LDFLAGS"
export LDCXXSHARED="clang++ -dynamiclib -undefined error $LDFLAGS"
run_ios_setup build --parallel 4
copy_package_files
find build -name '*.o' -print > build/aggregate-files.txt
# shellcheck disable=SC2086 # IOS_TARGET_FLAGS is a compiler argument list.
clang++ $IOS_TARGET_FLAGS -dynamiclib -undefined error -Wl,-filelist,build/aggregate-files.txt \
	-F"$PYTHON_FRAMEWORK_DIR" -framework Python -F"$IOS_NATIVE_DIR" -framework libgdal -framework ios_system -lz -lm \
	-o build/rasterio.so
install_site_package rasterio/rasterio build/rasterio.so
for library in build/lib.*/rasterio/*.so; do
	module=$(basename "$library"); module=${module%%.cpython-*}
	cp "$DIRECTORY/rasterio/rasterio.cpython-313-$ASHELL_SDK.fwork" "$DIRECTORY/rasterio/$module.cpython-313-$ASHELL_SDK.fwork"
done
popd
