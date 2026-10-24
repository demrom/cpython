#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/ios-meson-package-common.sh"
configure_meson_python shapely "$DIRECTORY/numpy/_core/include"
for name in libgeos libgeos_c; do test -f "$IOS_NATIVE_DIR/$name.framework/$name"; done
geos_version=$(awk '/^#define GEOS_VERSION / {gsub(/"/, "", $3); print $3}' "$IOS_NATIVE_DIR/libgeos_c.framework/Headers/geos_c.h")
test -n "$geos_version"
cat > "$IOS_NATIVE_DIR/lib/pkgconfig/geos.pc" <<PKGCONFIG
Name: geos
Description: iOS GEOS C framework
Version: $geos_version
Cflags: -I$IOS_NATIVE_DIR/libgeos_c.framework/Headers
Libs: -F$IOS_NATIVE_DIR -framework libgeos_c
PKGCONFIG
archive=$PREFIX/packages/shapely-2.2.0.tar.gz
mkdir -p "$PREFIX/packages"
if [[ ! -f $archive ]]; then
	curl -fL https://files.pythonhosted.org/packages/source/s/shapely/shapely-2.2.0.tar.gz -o "$archive.download"
	mv "$archive.download" "$archive"
fi
printf '%s  %s\n' e8865e553d874a1ec4a032057ea81fca9def37b188cd8fb550af3b3480b3f88c "$archive" | shasum -a 256 -c -
shapely_source=$PREFIX/build-$ASHELL_ARCH-$ASHELL_SDK/shapely-source
rm -rf "$shapely_source"
mkdir -p "$shapely_source"
tar -xzf "$archive" --strip-components 1 -C "$shapely_source"
meson setup --wipe "$MESON_BUILD_DIR" "$shapely_source" --cross-file "$MESON_CROSS_FILE" --native-file "$MESON_NATIVE_FILE" \
	--prefix "$PREFIX/Library" --buildtype release
meson compile -C "$MESON_BUILD_DIR" -j 4
meson install -C "$MESON_BUILD_DIR" --no-rebuild
while IFS= read -r -d '' library; do
	module=${library#"$DIRECTORY/"}
	module=${module%%.cpython-*}
	install_site_package "$module" "$library"
	rm "$library"
done < <(find "$DIRECTORY/shapely" -name "*.cpython-313-$ASHELL_SDK.so" -print0)
