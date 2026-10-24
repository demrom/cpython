#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/ios-meson-package-common.sh"
configure_meson_python sklearn "$DIRECTORY/numpy/_core/include"
source=$IOS_PACKAGE_ROOT/packages/scikit-learn
test "$(git -C "$source" rev-parse HEAD)" = c4eeb766e4d69a8d5daff23ab984af1354adc1ae
test -f "$IOS_NATIVE_DIR/libomp.framework/libomp"
scikit_source=$PREFIX/build-$ASHELL_ARCH-$ASHELL_SDK/sklearn-source
rm -rf "$scikit_source"
mkdir -p "$scikit_source"
git -C "$source" archive HEAD | tar -x -C "$scikit_source"
# Meson's Apple OpenMP detection selects the build host's Homebrew library.
# Bind this cross-build to the explicit target framework instead.
"$PYTHON_FOR_BUILD" - "$scikit_source/sklearn/meson.build" "$IOS_NATIVE_DIR" "${PYTHON_FOR_BUILD%/*}/cython" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
old = "openmp_dep = dependency('OpenMP', language: 'c', required: false)"
assert text.count(old) == 1
native = sys.argv[2]
new = f"openmp_dep = declare_dependency(compile_args: ['-Xpreprocessor', '-fopenmp', '-I{native}/libomp.framework/Headers'], link_args: ['-F{native}', '-framework', 'libomp'])"
text = text.replace(old, new)
old = "cython_program = find_program(cython.cmd_array()[0])"
assert text.count(old) == 1
text = text.replace(old, f"cython_program = find_program('{sys.argv[3]}')")
old = "scikit_learn_cython_args = ["
assert text.count(old) == 1
text = text.replace(old, old + "\n  '--cleanup', '3',")
old = "cython_program, '-3', '--fast-fail',"
assert text.count(old) == 1
text = text.replace(old, "cython_program, '-3', '--fast-fail', '--cleanup', '3',")
path.write_text(text)
PY
meson setup --wipe "$MESON_BUILD_DIR" "$scikit_source" --cross-file "$MESON_CROSS_FILE" --native-file "$MESON_NATIVE_FILE" \
	--prefix "$PREFIX/Library" --buildtype release
meson compile -C "$MESON_BUILD_DIR" -j 4
meson install -C "$MESON_BUILD_DIR" --no-rebuild
while IFS= read -r -d '' library; do
	module=${library#"$DIRECTORY/"}
	module=${module%%.cpython-*}
	header=$(otool -hv "$library")
	grep -q ' DYLIB ' <<< "$header"
	symbols=$(nm -m "$library")
	if grep -q 'dynamically looked up' <<< "$symbols"; then
		echo "Flat namespace lookup: $library" >&2
		exit 1
	fi
	install_site_package "$module" "$library"
	rm "$library"
done < <(find "$DIRECTORY/sklearn" -name "*.cpython-313-$ASHELL_SDK.so" -print0)
frameworks=("$CODESIGNING_FOLDER_PATH/Frameworks/Python-sklearn."*.framework)
test "${#frameworks[@]}" = 69
uv pip install --python "$PYTHON_FOR_BUILD" --target "$DIRECTORY" --no-deps --require-hashes --only-binary :all: \
	-r "$IOS_PACKAGE_ROOT/scripts/requirements-ios-full.txt"
