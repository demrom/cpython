#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/ios-package-common.sh"
prepare_ios_cython
extract_ios_source pygeos 0.14 30fbc17f64844200b85133b885fcfb65541b8779531f6ef4f8fe467d3fba7623
configure_ios_setup
export GEOS_INCLUDE_PATH=$IOS_NATIVE_DIR/libgeos_c.framework/Headers GEOS_LIBRARY_PATH=$IOS_NATIVE_DIR
export LDSHARED="$LDSHARED -framework libgeos_c" LDCXXSHARED="$LDCXXSHARED -framework libgeos_c"
"$PYTHON_FOR_BUILD" - "$IOS_SOURCE_DIR" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
path = root / "setup.py"
text = path.read_text()
for old, new in [('from pkg_resources import parse_version', 'from packaging.version import parse as parse_version'), ('"libraries": ["geos_c"],', '"libraries": [],')]:
    assert old in text
    text = text.replace(old, new)
path.write_text(text)
path = root / "pygeos/_geos.pyx"
text = path.read_text()
old = 'cdef void geos_message_handler(const char* message, void* userdata):'
assert old in text
path.write_text(text.replace(old, old[:-1] + ' noexcept:'))
path = root / "versioneer.py"
text = path.read_text()
assert 'configparser.SafeConfigParser()' in text and 'parser.readfp(f)' in text
path.write_text(text.replace('configparser.SafeConfigParser()', 'configparser.ConfigParser()').replace('parser.readfp(f)', 'parser.read_file(f)'))
for path in (root / 'src').glob('*.c'):
    text = path.read_text()
    if '#include <numpy/npy_3kcompat.h>' in text:
        text = text.replace('#include <numpy/npy_3kcompat.h>\n', '')
    if path.name == 'ufuncs.c':
        assert 'npy_intp* dimensions' in text and 'npy_intp* steps' in text
        text = text.replace('npy_intp* dimensions', 'const npy_intp* dimensions').replace('npy_intp* steps', 'const npy_intp* steps')
    path.write_text(text)
PY
pushd "$IOS_SOURCE_DIR"
run_ios_setup build --parallel 4
copy_package_files
for module in lib _geometry _geos; do
	install_site_package "pygeos/$module" build/lib.*/pygeos/"$module"*.so
done
popd
