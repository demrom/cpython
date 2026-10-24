#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/ios-meson-package-common.sh"
prepare_ios_cython
if [[ $# == 0 ]]; then set -- kiwisolver pillow contourpy matplotlib; fi
for package in "$@"; do
	case $package in
		kiwisolver)
			extract_ios_source kiwisolver 1.4.9 c3b22c26c6fd6811b0ae8363b95ca8ce4ea3c202d3d0975b2914310ceb1bcc4d
			configure_ios_setup
			# The solver's templated inline functions require size optimization.
			export CFLAGS="$CFLAGS -Oz" CPPFLAGS="$CPPFLAGS -Oz" CXXFLAGS="$CXXFLAGS -Oz"
			pushd "$IOS_SOURCE_DIR"
			run_ios_setup build --parallel 4
			copy_package_files
			install_site_package kiwisolver/_cext build/lib.*/kiwisolver/_cext*.so
			popd ;;
		pillow)
			extract_ios_source pillow 11.3.0 3828ee7586cd0b2091b6209e5ad53e20d0649bbe87164a459d0676e035e8f523
			configure_ios_setup
			codec_lib=$PREFIX/build-$ASHELL_ARCH-$ASHELL_SDK/pillow-libs
			mkdir -p "$codec_lib"
			for spec in freetype:freetype libpng:png; do
				framework=${spec%:*}; library=${spec#*:}
				test -f "$IOS_NATIVE_DIR/$framework.framework/$framework"
				ln -sfn "$IOS_NATIVE_DIR/$framework.framework/$framework" "$codec_lib/lib$library.dylib"
				export CFLAGS="$CFLAGS -I$IOS_NATIVE_DIR/$framework.framework/Headers"
			done
			for library in jpeg tiff; do
				test -f "$IOS_NATIVE_DIR/lib/lib$library.a"
				test -d "$IOS_NATIVE_DIR/include/$library"
				export CFLAGS="$CFLAGS -I$IOS_NATIVE_DIR/include/$library"
			done
			export CFLAGS="$CFLAGS -I$IOS_SDKROOT/usr/include"
			export CPPFLAGS=$CFLAGS CXXFLAGS=$CFLAGS
			export LDFLAGS="$LDFLAGS -L$IOS_SDKROOT/usr/lib -L$codec_lib -L$IOS_NATIVE_DIR/lib -ljpeg -ltiff -lfreetype -lpng"
			export LDSHARED="clang -dynamiclib -undefined error $LDFLAGS" MAX_CONCURRENCY=4
			pushd "$IOS_SOURCE_DIR"
			# Match the existing recipe's JPEG/TIFF/FreeType/zlib dependency set.
			run_ios_setup build_ext --parallel 4 --disable-platform-guessing --enable-jpeg --enable-zlib --enable-tiff --enable-freetype \
				--disable-lcms --disable-webp --disable-avif --disable-jpeg2000 --disable-imagequant --disable-xcb --disable-raqm build
			copy_package_files
			install_setup_aggregate PIL
			popd ;;
		contourpy|matplotlib)
			configure_meson_python "$package" "$DIRECTORY/numpy/_core/include"
			options=()
			if [[ $package == contourpy ]]; then
				extract_ios_source contourpy 1.3.3 083e12155b210502d0bca491432bb04d56dc3432f95a979b429f2848c3dbe880
				options=(-Dwerror=false)
			else
				extract_ios_source matplotlib 800b734 2411d2645194a9e5b1c90db4e90d4a8c56730038a852d0fbe2fe629288e47ee2 \
					https://github.com/holzschu/matplotlib/archive/800b7346261205457cf5aa990ee890fd2eab0e9e.tar.gz
				test -f "$IOS_NATIVE_DIR/freetype.framework/freetype"
				cat > "$IOS_NATIVE_DIR/lib/pkgconfig/freetype2.pc" <<PKGCONFIG
Name: freetype2
Description: iOS FreeType framework
Version: 23.2.17
Cflags: -I$IOS_NATIVE_DIR/freetype.framework/Headers
Libs: -F$IOS_NATIVE_DIR -framework freetype
PKGCONFIG
				export SETUPTOOLS_SCM_PRETEND_VERSION=0.0+g800b734
				options=(-Dmacosx=false -Dsystem-freetype=true -Db_lto=false)
			fi
			meson setup --wipe "$MESON_BUILD_DIR" "$IOS_SOURCE_DIR" --cross-file "$MESON_CROSS_FILE" --native-file "$MESON_NATIVE_FILE" \
				--prefix "$PREFIX/Library" --buildtype release "${options[@]}"
			meson compile -C "$MESON_BUILD_DIR" -j 4
			meson install -C "$MESON_BUILD_DIR" --no-rebuild
			while IFS= read -r -d '' library; do
				module=${library#"$DIRECTORY/"}; module=${module%%.cpython-*}
				# a-Shell's project keeps backend framework names at the package root.
				framework_module=${module/\/backends\//\/}
				install_site_package "$framework_module" "$library"
				if [[ $framework_module != "$module" ]]; then
					mv "$DIRECTORY/$framework_module.cpython-313-$ASHELL_SDK.fwork" "$DIRECTORY/$module.cpython-313-$ASHELL_SDK.fwork"
				fi
				rm "$library"
			done < <(find "$DIRECTORY/$package" -name "*.cpython-313-$ASHELL_SDK.so" -print0)
			;;
		*) echo "Unsupported graphics package: $package" >&2; exit 1 ;;
	esac
done
