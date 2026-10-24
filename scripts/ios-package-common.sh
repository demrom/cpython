#!/bin/bash

# Shared target and framework packaging for the iOS package recipes.
IOS_PACKAGE_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export PREFIX=${PREFIX:-$PWD}
export ASHELL_SDK=${ASHELL_SDK:-iphoneos}
export ASHELL_ARCH=${ASHELL_ARCH:-arm64}
export ASHELL_MIN_IOS=${ASHELL_MIN_IOS:-14.0}
export PYTHON_FOR_BUILD=${PYTHON_FOR_BUILD:-python3.13}
case "$ASHELL_SDK:$ASHELL_ARCH" in
  iphoneos:arm64) IOS_TRIPLE=arm64-apple-ios$ASHELL_MIN_IOS; IOS_PLATFORM=iPhoneOS ;;
  iphonesimulator:arm64|iphonesimulator:x86_64) IOS_TRIPLE=$ASHELL_ARCH-apple-ios$ASHELL_MIN_IOS-simulator; IOS_PLATFORM=iPhoneSimulator ;;
  *) echo "Unsupported target: $ASHELL_SDK:$ASHELL_ARCH" >&2; exit 1 ;;
esac
IOS_SDKROOT=$(xcrun --sdk "$ASHELL_SDK" --show-sdk-path)
export IOS_SDKROOT
export SDKROOT=$IOS_SDKROOT
export IOS_NATIVE_DIR=${IOS_NATIVE_DIR:-$PREFIX/Frameworks_$ASHELL_SDK}
export PYTHON_FRAMEWORK_DIR=${PYTHON_FRAMEWORK_DIR:-$PREFIX/ios/Frameworks/$ASHELL_ARCH-$ASHELL_SDK}
export IOS_TARGET_FLAGS="-target $IOS_TRIPLE -isysroot $IOS_SDKROOT -I$PYTHON_FRAMEWORK_DIR/Python.framework/Headers"
export PATH=$PREFIX/Library/bin:$PATH
export PYTHONPYCACHEPREFIX=$PREFIX/__pycache__
export DEBUG="-O3 -g -Wall"
export CYTHON_OPTIONS="-DCYTHON_PEP489_MULTI_PHASE_INIT=0 -DCYTHON_USE_DICT_VERSIONS=0 -DCYTHON_USE_PYTYPE_LOOKUP=0"
APP=$(basename "$(dirname "$PREFIX")")
export APP
CODESIGNING_FOLDER_PATH=$PREFIX/iOS
PRODUCT_BUNDLE_IDENTIFIER=Nicolas-Holzschuch
DIRECTORY=$PREFIX/Library/lib/python3.13/site-packages
mkdir -p "$DIRECTORY"

prepare_ios_cython() {
	local tools=$IOS_PACKAGE_ROOT/.build/science-tools archive cython_source
	archive=$tools/cython-bcd04a2.tar.gz
	cython_source=$tools/cython-source
	test -f "$tools/bin/python" || uv venv --python 3.13.15 "$tools"
	uv pip install --python "$tools/bin/python" -r "$IOS_PACKAGE_ROOT/scripts/requirements-ios-science.txt"
	if [[ ! -f $archive ]]; then
		curl -fL --retry 3 https://github.com/cython/cython/archive/bcd04a2966842d80de6ecff4e68e8d892bec5ef7.tar.gz -o "$archive"
	fi
	printf '%s  %s\n' 59f060b075908af9a398052ac6d869f68db1c40f211a111cb5fa6ecda14d0c7b "$archive" | shasum -a 256 -c -
	rm -rf "$cython_source"
	mkdir -p "$cython_source"
	tar -xzf "$archive" --strip-components=1 -C "$cython_source"
	# Cython #8082, #8083 and #8084: constant defaults and cleanup-safe re-entry.
	patch -p1 -f -d "$cython_source" -i "$IOS_PACKAGE_ROOT/packages/cython-ios-reentry.patch"
	NO_CYTHON_COMPILE=true uv pip install --no-build-isolation --no-cache --reinstall-package cython --python "$tools/bin/python" "$cython_source"
	export PATH=$tools/bin:$PATH PYTHON_FOR_BUILD=$tools/bin/python
	export CYTHON_OPTIONS="$CYTHON_OPTIONS -DCYTHON_USE_TYPE_SPECS=1 -DCYTHON_USE_MODULE_STATE=0"
}

run_ios_setup() {
	"$PYTHON_FOR_BUILD" -c 'import runpy, sys; from Cython.Compiler import Options; Options.generate_cleanup_code = 3; sys.argv = ["setup.py", *sys.argv[1:]]; runpy.run_path("setup.py", run_name="__main__")' "$@"
}

copy_package_files() {
	local directory
	for directory in build/lib.*; do
		test -d "$directory"
		cp -R "$directory/" "$DIRECTORY/"
	done
	"$PYTHON_FOR_BUILD" setup.py egg_info --egg-base "$DIRECTORY"
	# Native modules are installed as frameworks by install_site_package.
	find "$DIRECTORY" -name '*.so' -delete
}

install_site_package() {
	test "$#" -eq 2
	local package=$1 library=$2 name framework bundle_id
	name=Python-${package//\//.}
	framework=$CODESIGNING_FOLDER_PATH/Frameworks/$name.framework
	bundle_id=${PRODUCT_BUNDLE_IDENTIFIER}.${name//_/-}
	mkdir -p "$framework" "$(dirname "$DIRECTORY/$package")"
	cp "$IOS_PACKAGE_ROOT/iOS/Resources/dylib-Info-template.plist" "$framework/Info.plist"
	plutil -replace CFBundleExecutable -string "$name" "$framework/Info.plist"
	plutil -replace CFBundleIdentifier -string "$bundle_id" "$framework/Info.plist"
	plutil -replace CFBundleName -string "$name" "$framework/Info.plist"
	plutil -replace CFBundleSupportedPlatforms.0 -string "$IOS_PLATFORM" "$framework/Info.plist"
	plutil -replace MinimumOSVersion -string "$ASHELL_MIN_IOS" "$framework/Info.plist"
	cp "$library" "$framework/$name"
	install_name_tool -id "@rpath/$name.framework/$name" "$framework/$name"
	echo "Frameworks/$name.framework/$name" > "$DIRECTORY/$package.cpython-313-$ASHELL_SDK.fwork"
	echo "lib/python3.13/site-packages/$package.cpython-313-$ASHELL_SDK.so" > "$framework/$name.origin"
}
