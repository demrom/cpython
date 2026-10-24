#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/ios-meson-package-common.sh"
configure_meson_python pandas "$DIRECTORY/numpy/_core/include"
archive=$PREFIX/packages/pandas-3.1.0.tar.gz
mkdir -p "$PREFIX/packages"
if [[ ! -f $archive ]]; then
	curl -fL https://files.pythonhosted.org/packages/source/p/pandas/pandas-3.1.0.tar.gz -o "$archive.download"
	mv "$archive.download" "$archive"
fi
printf '%s  %s\n' ecb9b2d8a817b1e1ba1fdb90c0abe9eab31b4fdf2562b7a56b86ac66ace17e49 "$archive" | shasum -a 256 -c -
pandas_source=$PREFIX/build-$ASHELL_ARCH-$ASHELL_SDK/pandas-source
rm -rf "$pandas_source"
mkdir -p "$pandas_source"
tar -xzf "$archive" --strip-components 1 -C "$pandas_source"
meson setup --wipe "$MESON_BUILD_DIR" "$pandas_source" --cross-file "$MESON_CROSS_FILE" --native-file "$MESON_NATIVE_FILE" \
	--prefix "$PREFIX/Library" --buildtype release
meson compile -C "$MESON_BUILD_DIR" -j 4
meson install -C "$MESON_BUILD_DIR" --no-rebuild
while IFS= read -r -d '' library; do
	module=${library#"$DIRECTORY/"}
	module=${module%%.cpython-*}
	install_site_package "$module" "$library"
	rm "$library"
done < <(find "$DIRECTORY/pandas" -name "*.cpython-313-$ASHELL_SDK.so" -print0)
# Pin and verify Pandas' pure-Python runtime dependencies.
uv pip install --python "$PYTHON_FOR_BUILD" --target "$DIRECTORY" --no-deps --require-hashes --only-binary :all: \
	-r "$IOS_PACKAGE_ROOT/scripts/requirements-ios-pandas.txt"
