#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/ios-package-common.sh"
prepare_ios_cython
# Nested source revisions of the existing opencv-python ac63f5b gitlink.
extract_ios_source opencv 69357b1 1eda61564b06799e85b081512b8a56d9a962498ed14e96611e09701e26b30816 https://github.com/opencv/opencv/archive/69357b1e88680658a07cffde7678a4d697469f03.tar.gz
opencv_source=$IOS_SOURCE_DIR
extract_ios_source opencv_contrib f5d7f67 5a3323aad04ec31b488df9c6262f9a5b6286d467555d01887d31c35ef5430875 https://github.com/opencv/opencv_contrib/archive/f5d7f6712d4ff229ba4f45cf79dfd11c557d56fd.tar.gz
contrib_source=$IOS_SOURCE_DIR
extract_ios_source opencv-python ac63f5b 8b691eacdd8824394a009141bab4b3737deb3d7f7e6cb17b2ea758c408ffb677 https://github.com/holzschu/opencv-python/archive/ac63f5b0e67cb2c54aefeac107c10d3a3789066c.tar.gz
cp -R "$IOS_SOURCE_DIR/cv2/" "$DIRECTORY/cv2/"
cp "$opencv_source/data/haarcascades/"*.xml "$DIRECTORY/cv2/data/"
configure_ios_setup
"$PYTHON_FOR_BUILD" - "$opencv_source/modules/python/common.cmake" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
old = 'ocv_add_library(${the_module} MODULE '
assert old in text and '-undefined dynamic_lookup' in text
path.write_text(text.replace(old, 'ocv_add_library(${the_module} SHARED ').replace('-undefined dynamic_lookup', '-undefined error'))
PY
# Apple SDK headers also declare Point, Size, Rect and Ptr in the global namespace.
"$PYTHON_FOR_BUILD" - "$opencv_source/modules/python/src2/cv2.cpp" <<'PYTHON'
from pathlib import Path
import re
import sys
path = Path(sys.argv[1])
text = path.read_text()
text, count = re.subn(r"(?<![:\w])(Point|Size|Rect|Ptr)\b", r"cv::\1", text)
assert count == 11, count
path.write_text(text)
PYTHON
"$PYTHON_FOR_BUILD" - "$opencv_source/modules/python/src2/gen2.py" <<'PYTHON'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
assert text.count('Ptr<') == 6
text = text.replace('Ptr<', 'cv::Ptr<')
old = '    return tp\n\n\nclass ArgInfo'
assert old in text
text = text.replace(old, '    return re.sub(r"(?<![:\\w])(Point|Size|Rect|Ptr)\\b", r"cv::\\1", tp)\n\n\nclass ArgInfo')
text = text.replace('self.rettype = decl[4] or handle_ptr(decl[1])', 'self.rettype = handle_ptr(decl[4] or decl[1])')
text = text.replace('self.defval = arg_tuple[2]', 'self.defval = handle_ptr(arg_tuple[2])')
text = text.replace('pass_by_val_types = ["Point*", "Point2f*", "Rect*",', 'pass_by_val_types = ["cv::Point*", "Point2f*", "cv::Rect*",')
text = text.replace('mappable=mappable', 'mappable=handle_ptr(mappable)')
path.write_text(text)
PYTHON
"$PYTHON_FOR_BUILD" - "$opencv_source/modules/python/src2/pycompat.hpp" <<'PYTHON'
from pathlib import Path
import re
import sys
path = Path(sys.argv[1])
text, count = re.subn(r"(?<![:\w])Ptr<", "cv::Ptr<", path.read_text())
assert count == 4, count
path.write_text(text)
PYTHON
"$PYTHON_FOR_BUILD" - "$opencv_source" "$contrib_source" <<'PYTHON'
from pathlib import Path
import re
import sys
for root in sys.argv[1:]:
    for path in Path(root).glob('modules/*/misc/python/pyopencv_*.hpp'):
        text = path.read_text()
        text = re.sub(r"(?<![:\w])Ptr<", "cv::Ptr<", text)
        path.write_text(text)
PYTHON
build=$PREFIX/build-$ASHELL_ARCH-$ASHELL_SDK/opencv
cmake -S "$opencv_source" -B "$build" -G Ninja \
	-DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_SYSTEM_NAME=iOS \
	-DCMAKE_OSX_SYSROOT="$IOS_SDKROOT" -DCMAKE_OSX_ARCHITECTURES="$ASHELL_ARCH" \
	-DCMAKE_OSX_DEPLOYMENT_TARGET="$ASHELL_MIN_IOS" -DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_SHARED_LINKER_FLAGS="$LDFLAGS -framework Foundation -framework CoreFoundation -lobjc" -DBUILD_SHARED_LIBS=OFF \
	-DOPENCV_EXTRA_MODULES_PATH="$contrib_source/modules" \
	-DAPPLE_FRAMEWORK=OFF -DBUILD_TESTS=OFF -DBUILD_PERF_TESTS=OFF \
	-DENABLE_CCACHE=OFF \
	-DBUILD_ZLIB=OFF -DZLIB_INCLUDE_DIR="$IOS_SDKROOT/usr/include" -DZLIB_LIBRARY="$IOS_SDKROOT/usr/lib/libz.tbd" \
	-DBUILD_PNG=OFF -DPNG_PNG_INCLUDE_DIR="$IOS_NATIVE_DIR/libpng.framework/Headers" -DPNG_LIBRARY="$IOS_NATIVE_DIR/libpng.framework/libpng" \
	-DBUILD_JPEG=OFF -DJPEG_INCLUDE_DIR="$IOS_NATIVE_DIR/include/jpeg" -DJPEG_LIBRARY="$IOS_NATIVE_DIR/lib/libjpeg.a" \
	-DBUILD_TIFF=OFF -DTIFF_INCLUDE_DIR="$IOS_NATIVE_DIR/include/tiff" -DTIFF_LIBRARY="$IOS_NATIVE_DIR/lib/libtiff.a" \
	-DBUILD_EXAMPLES=OFF -DBUILD_opencv_apps=OFF -DBUILD_JAVA=OFF \
	-DBUILD_opencv_python2=OFF -DBUILD_opencv_python3=ON \
	-DWITH_QT=OFF -DWITH_GTK=OFF -DWITH_COCOA=OFF \
	-DPYTHON_DEFAULT_EXECUTABLE="$PYTHON_FOR_BUILD" -DPYTHON3_EXECUTABLE="$PYTHON_FOR_BUILD" \
	-DPYTHON_DEFAULT_AVAILABLE=ON -DPYTHON3INTERP_FOUND=ON -DPYTHON3LIBS_FOUND=ON \
	-DPYTHON3_VERSION_MAJOR=3 -DPYTHON3_VERSION_MINOR=13 -DPYTHON3_VERSION_STRING=3.13.15 \
	-DPYTHON3_INCLUDE_DIR="$PYTHON_FRAMEWORK_DIR/Python.framework/Headers" \
	-DPYTHON3_INCLUDE_PATH="$PYTHON_FRAMEWORK_DIR/Python.framework/Headers" \
	-DPYTHON3_LIBRARY="$PYTHON_FRAMEWORK_DIR/Python.framework/Python" \
	-DPYTHON3_NUMPY_INCLUDE_DIRS="$DIRECTORY/numpy/_core/include" \
	-DPYTHON3_NUMPY_VERSION=2.3.1 \
	-DPYTHON3_CVPY_SUFFIX=.so
cmake --build "$build" --target opencv_python3 --parallel 4
install_site_package cv2/cv2 "$build/lib/python3/cv2.so"
