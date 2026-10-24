#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/ios-package-common.sh"
prepare_ios_cython

pushd "$PREFIX/packages/statsmodels"
rm -rf build
numpy=$DIRECTORY/numpy/_core
# Search target NumPy headers and libraries before setuptools' build-host paths.
export CC="clang $IOS_TARGET_FLAGS" CXX="clang++ $IOS_TARGET_FLAGS"
export CFLAGS="$IOS_TARGET_FLAGS -I$numpy/include $CYTHON_OPTIONS"
export CXXFLAGS="$IOS_TARGET_FLAGS -I$numpy/include $CYTHON_OPTIONS"
export LDSHARED="clang $IOS_TARGET_FLAGS -dynamiclib -undefined error -L$numpy/lib -F$PYTHON_FRAMEWORK_DIR -framework Python -F$IOS_NATIVE_DIR -framework ios_system -lz -lc++"
export PLATFORM=$ASHELL_SDK
run_ios_setup build --parallel 4
copy_package_files

# Keep the existing aggregate, excluding three filters that collide with smoothers.
filelist=$PREFIX/statsmodels-aggregate-files.txt
find build -not -path '*/_filters/*' -name '*.o' -print > "$filelist"
printf '%s\n' build/temp.*/statsmodels/tsa/statespace/_filters/_inversions.o >> "$filelist"
# shellcheck disable=SC2086 # IOS_TARGET_FLAGS is a compiler argument list.
clang $IOS_TARGET_FLAGS -dynamiclib -undefined error -Wl,-filelist,"$filelist" \
	-F"$PYTHON_FRAMEWORK_DIR" -framework Python -L"$numpy/lib" -lnpymath \
	-L"$DIRECTORY/numpy/random/lib" -lnpyrandom -F"$IOS_NATIVE_DIR" -framework ios_system -lz -lm -lc++ -o build/statsmodels.so
install_site_package statsmodels/statsmodels build/statsmodels.so
while IFS= read -r library; do
	module=${library#build/lib.*/}
	module=${module%%.cpython-*}
	cp "$DIRECTORY/statsmodels/statsmodels.cpython-313-$ASHELL_SDK.fwork" \
		"$DIRECTORY/$module.cpython-313-$ASHELL_SDK.fwork"
done < <(find build/lib.*/statsmodels -name '*.so' -print)
for name in _univariate_diffuse _univariate _conventional; do
	install_site_package "statsmodels/tsa/statespace/_filters/$name" \
		build/lib.*/statsmodels/tsa/statespace/_filters/$name.cpython-313-*.so
done
popd
