#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/ios-package-common.sh"
prepare_ios_cython
if [[ $# == 0 ]]; then set -- pyerfa astropy; fi
for package in "$@"; do
	case $package in
		pyerfa) extract_ios_source pyerfa 2.0.1.5 17d6b24fe4846c65d5e7d8c362dcb08199dc63b30a236aedd73875cc83e1f6c0 ;;
		astropy) extract_ios_source astropy 7.1.1 6d128f0005e2c34f70113484468bf9d0e4ca1ee15a279cfd08bdd979d38db0f8 ;;
		*) echo "Unsupported astronomy package: $package" >&2; exit 1 ;;
	esac
	configure_ios_setup
	pushd "$IOS_SOURCE_DIR"
	run_ios_setup build --parallel 4
	copy_package_files
	case $package in
		pyerfa) install_site_package erfa/ufunc build/lib.*/erfa/ufunc*.so ;;
		astropy) install_setup_aggregate astropy ;;
	esac
	popd
done
