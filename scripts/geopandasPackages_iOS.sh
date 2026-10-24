#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/ios-package-common.sh"
prepare_ios_cython
if [[ $# == 0 ]]; then set -- shapely fiona pyproj rasterio; fi
for package in "$@"; do
	case $package in
		shapely|rasterio)
			bash "$IOS_PACKAGE_ROOT/scripts/${package}Packages_iOS.sh"
			continue ;;
		fiona)
			extract_ios_source fiona 1.10.1 b00ae357669460c6491caba29c2022ff0acfcbde86a95361ea8ff5cd14a86b68
			configure_ios_setup
			test -f "$IOS_NATIVE_DIR/libgdal.framework/libgdal"
			export GDAL_CONFIG=/usr/bin/false
			GDAL_VERSION=$(awk '/^#[[:space:]]*define GDAL_VERSION_MAJOR[[:space:]]/ {major=$NF} /^#[[:space:]]*define GDAL_VERSION_MINOR[[:space:]]/ {minor=$NF} /^#[[:space:]]*define GDAL_VERSION_REV[[:space:]]/ {rev=$NF} END {print major "." minor "." rev}' "$IOS_NATIVE_DIR/libgdal.framework/Headers/gdal_version.h")
			[[ $GDAL_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
			export GDAL_VERSION
			export CFLAGS="$CFLAGS -I$IOS_NATIVE_DIR/libgdal.framework/Headers"
			export CPPFLAGS=$CFLAGS CXXFLAGS=$CFLAGS
			export LDSHARED="$LDSHARED -framework libgdal" LDCXXSHARED="$LDCXXSHARED -framework libgdal"
			;;
		pyproj)
			extract_ios_source pyproj 3.6.1 44aa7c704c2b7d8fb3d483bbf75af6cb2350d30a63b144279a09b75fead501bf
			configure_ios_setup
			test -f "$IOS_NATIVE_DIR/libproj.framework/libproj"
			export PROJ_DIR=$IOS_NATIVE_DIR PROJ_LIBDIR=$IOS_NATIVE_DIR PROJ_INCDIR=$IOS_NATIVE_DIR/libproj.framework/Headers
			PROJ_VERSION=$(awk '/^#define PROJ_VERSION_MAJOR / {major=$3} /^#define PROJ_VERSION_MINOR / {minor=$3} /^#define PROJ_VERSION_PATCH / {patch=$3} END {print major "." minor "." patch}' "$PROJ_INCDIR/proj.h")
			[[ $PROJ_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
			export PROJ_VERSION
			# Link the target framework; do not probe a host PROJ library or add its rpath.
			"$PYTHON_FOR_BUILD" - "$IOS_SOURCE_DIR/setup.py" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
old = '"libraries": get_libraries(library_dirs),'
assert old in text
text = text.replace(old, '"libraries": [],')
old = 'library_dirs if os.name != "nt" and sys.platform != "cygwin" else None'
assert old in text
path.write_text(text.replace(old, 'None'))
PY
			export LDSHARED="$LDSHARED -framework libproj" LDCXXSHARED="$LDCXXSHARED -framework libproj"
			;;
		*) echo "Unsupported GIS package: $package" >&2; exit 1 ;;
	esac
	pushd "$IOS_SOURCE_DIR"
	run_ios_setup build --parallel 4
	copy_package_files
	case $package in
		fiona) install_setup_aggregate fiona -framework libgdal ;;
		pyproj) install_setup_aggregate pyproj -framework libproj ;;
	esac
	popd
done
