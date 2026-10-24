#!/bin/bash
set -euo pipefail

# Reuse the core/science outputs; build the remaining full-app package recipes.
source_root=$(cd "$(dirname "$0")/.." && pwd)
core_root=$(cd "${1:?Pass the core Python build directory}" && pwd)
science_root=$(cd "${2:?Pass the scientific Python build directory}" && pwd)
native_root=$(cd "${3:?Pass the native xcframework directory}" && pwd)
mkdir -p "${4:-$source_root/.build/full}"
build_root=$(cd "${4:-$source_root/.build/full}" && pwd)
export ASHELL_MIN_IOS=14.0
for target in iphoneos iphonesimulator iphonesimulator-x86_64; do
	export ASHELL_SDK=${target%%-*} ASHELL_ARCH=arm64
	[[ $target != iphonesimulator-x86_64 ]] || ASHELL_ARCH=x86_64
	export PREFIX=$build_root/$target
	export IOS_NATIVE_DIR=$PREFIX/native PYTHON_FRAMEWORK_DIR=$core_root/install/$target
	export PYTHON_SYSCONFIGDATA=$PYTHON_FRAMEWORK_DIR/lib/python3.13/_sysconfigdata__ios_$ASHELL_ARCH-$ASHELL_SDK.py
	slice=ios-arm64
	[[ $ASHELL_SDK != iphonesimulator ]] || slice=ios-arm64_x86_64-simulator
	site=$PREFIX/Library/lib/python3.13/site-packages
	rm -rf "$PREFIX/Library" "$PREFIX/iOS" "$IOS_NATIVE_DIR"
	mkdir -p "$site" "$IOS_NATIVE_DIR/lib" "$IOS_NATIVE_DIR/include" "$PREFIX/packages"
	ln -s "$science_root/$target/Library/lib/python3.13/site-packages/numpy" "$site/numpy"
	ln -s "$core_root/ios-system-$target/Build/Products/Release-$ASHELL_SDK/ios_system.framework" "$IOS_NATIVE_DIR/ios_system.framework"
	for name in openblas flang_rt libomp libzmq libgeos libgeos_c libproj libgdal freetype libpng; do
		ln -s "$native_root/$name.xcframework/$slice/$name.framework" "$IOS_NATIVE_DIR/$name.framework"
	done
	for name in jpeg tiff; do
		ln -s "$native_root/lib$name.xcframework/$slice/lib$name.a" "$IOS_NATIVE_DIR/lib/lib$name.a"
		ln -s "$native_root/lib$name.xcframework/$slice/Headers" "$IOS_NATIVE_DIR/include/$name"
	done
	for name in fftw3 fftw3_threads fftw3f fftw3f_threads fftw3l fftw3l_threads; do
		ln -s "$native_root/lib$name.xcframework/$slice/lib$name.a" "$IOS_NATIVE_DIR/lib/lib$name.a"
	done
	ln -s "$native_root/libfftw3.xcframework/$slice/Headers/fftw3.h" "$IOS_NATIVE_DIR/include/fftw3.h"
	# These two existing submodule recipes retain their source ownership and pins.
	for name in word_cloud statsmodels; do
		ln -sfn "$source_root/packages/$name" "$PREFIX/packages/$name"
	done
	bash "$source_root/scripts/graphPackages_iOS.sh"
	bash "$source_root/scripts/geopandasPackages_iOS.sh" fiona pyproj rasterio
	bash "$source_root/scripts/astropyPackages_iOS.sh"
	bash "$source_root/scripts/cartopyPackages_iOS.sh"
	bash "$source_root/scripts/jupyterPackages_iOS.sh" argon2 psutil pyzmq
	bash "$source_root/scripts/pygeosPackages_iOS.sh"
	bash "$source_root/scripts/qutipPackages_iOS.sh"
	bash "$source_root/scripts/pandasPackages_iOS.sh" pyfftw cvxopt
	bash "$source_root/scripts/coreMLToolsPackages_iOS.sh"
	bash "$source_root/scripts/opencvPackages_iOS.sh"
	bash "$source_root/scripts/langPackages_iOS.sh"
	bash "$source_root/scripts/statsmodelsPackages_iOS.sh"
	bash "$source_root/scripts/scikitLearnPackages_iOS.sh"
	frameworks=("$PREFIX/iOS/Frameworks/"*.framework)
	test "${#frameworks[@]}" = 114
	for framework in "${frameworks[@]}"; do
		name=$(basename "$framework" .framework)
		test "$(lipo -archs "$framework/$name")" = "$ASHELL_ARCH"
		xcrun vtool -show-build "$framework/$name"
		otool -L "$framework/$name"
	done > "$PREFIX/framework-audit.txt"
	# Keep configuration and generator receipts before reclaiming intermediates.
	(
		cd "$PREFIX"
		find "build-$ASHELL_ARCH-$ASHELL_SDK" build-coreml-host -type f \( -name '*.log' -o -name '*.json' -o -name '*.txt' -o -name '*.ninja' \) -print0 > build-receipts.nul
		(
			cd "$source_root"
			find packages/word_cloud/build packages/statsmodels/build -type f \( -name '*.log' -o -name '*.json' -o -name '*.txt' \) -print0
		) > submodule-build-receipts.nul
		tar -czf build-receipts.tar.gz --null -T build-receipts.nul
		tar -czf submodule-build-receipts.tar.gz -C "$source_root" --null -T "$PREFIX/submodule-build-receipts.nul"
		tar -tzf build-receipts.tar.gz > build-receipts.txt
		tar -tzf submodule-build-receipts.tar.gz >> build-receipts.txt
		shasum -a 256 build-receipts.tar.gz submodule-build-receipts.tar.gz > build-receipts.sha256
	)
	rm -rf "$PREFIX/build-$ASHELL_ARCH-$ASHELL_SDK" "$PREFIX/build-coreml-host"
	rm -rf "$source_root/packages/word_cloud/build" "$source_root/packages/statsmodels/build"
done

diff <(ls "$build_root/iphoneos/iOS/Frameworks") <(ls "$build_root/iphonesimulator/iOS/Frameworks")
diff <(ls "$build_root/iphoneos/iOS/Frameworks") <(ls "$build_root/iphonesimulator-x86_64/iOS/Frameworks")
mkdir -p "$build_root/universal" "$build_root/dist"
: > "$build_root/dist/full-checksums.txt"
for device in "$build_root/iphoneos/iOS/Frameworks/"*.framework; do
	name=$(basename "$device" .framework)
	framework=$build_root/universal/$name.framework
	rm -rf "$framework" "$build_root/dist/$name.xcframework" "$build_root/dist/$name.xcframework.zip"
	cp -R "$build_root/iphonesimulator/iOS/Frameworks/$name.framework" "$framework"
	lipo -create "$framework/$name" "$build_root/iphonesimulator-x86_64/iOS/Frameworks/$name.framework/$name" -output "$framework/$name.universal"
	mv "$framework/$name.universal" "$framework/$name"
	xcodebuild -create-xcframework -framework "$device" -framework "$framework" -output "$build_root/dist/$name.xcframework"
	(cd "$build_root/dist" && zip --symlinks -rq "$name.xcframework.zip" "$name.xcframework")
	printf '%s  %s\n' "$(swift package compute-checksum "$build_root/dist/$name.xcframework.zip")" "$name.xcframework.zip" >> "$build_root/dist/full-checksums.txt"
done
rm -rf "$build_root/stdlib"
for target in iphoneos iphonesimulator; do
	mkdir -p "$build_root/stdlib/$target/lib/python3.13/site-packages"
	for package in "$build_root/$target/Library/lib/python3.13/site-packages/"*; do
		[[ ${package##*/} != numpy ]] || continue
		cp -R "$package" "$build_root/stdlib/$target/lib/python3.13/site-packages/"
	done
done
find "$build_root/stdlib" -type d -name __pycache__ -prune -exec rm -rf {} +
if find "$build_root/stdlib" -type f -exec file {} + | grep 'Mach-O'; then
	echo 'Native binary found in Python package data' >&2
	exit 1
fi
tar -czf "$build_root/dist/python-full.tar.gz" -C "$build_root/stdlib" iphoneos/lib iphonesimulator/lib
(cd "$build_root/dist" && shasum -a 256 python-full.tar.gz) >> "$build_root/dist/full-checksums.txt"
