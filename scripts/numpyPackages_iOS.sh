#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/ios-meson-package-common.sh"
numpy_source=$PREFIX/packages/numpy
numpy_revision=$(git -C "$IOS_PACKAGE_ROOT" rev-parse HEAD:packages/numpy)
test "$(git -C "$numpy_source" rev-parse HEAD)" = "$numpy_revision" || {
	echo "NumPy source does not match the pinned submodule revision: $numpy_revision" >&2
	exit 1
}
configure_meson_python numpy
meson_command=("$PYTHON_FOR_BUILD" "$numpy_source/vendored-meson/meson/meson.py")
"${meson_command[@]}" setup --wipe "$MESON_BUILD_DIR" "$numpy_source" --cross-file "$MESON_CROSS_FILE" --native-file "$MESON_NATIVE_FILE" \
	--prefix "$PREFIX/Library" --buildtype release -Dblas=openblas -Dlapack=openblas -Dallow-noblas=false
"${meson_command[@]}" compile -C "$MESON_BUILD_DIR" -j 4
"${meson_command[@]}" install -C "$MESON_BUILD_DIR" --no-rebuild

# Keep one copy of shared helpers and use the built static libraries for their objects.
filelist=$MESON_BUILD_DIR/aggregate-files.txt
: > "$filelist"
while IFS= read -r -d '' object; do
	case "$object" in
		*.a.p/*|*/lapack_lite.cpython-*/*lapack_lite_f2c*.o|*/lapack_lite_python_xerbla.c.o) continue ;;
		*/_multiarray_tests.cpython-*/src_common_*.o|*/_umath_tests.cpython-*/src_common_*.o|*/_simd.cpython-*/src_common_*.o) continue ;;
	esac
	printf '%s\n' "$object" >> "$filelist"
done < <(find "$MESON_BUILD_DIR/numpy" -name '*.o' -print0)
find "$MESON_BUILD_DIR/numpy" -name '*.a' -print >> "$filelist"
link_meson_aggregate numpy "$filelist"
alias_meson_extensions numpy
