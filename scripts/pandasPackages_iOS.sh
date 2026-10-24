#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/ios-package-common.sh"
prepare_ios_cython
if [[ $# == 0 ]]; then set -- pyfftw cvxopt pandas; fi
for package in "$@"; do
	case $package in
		pandas) bash "$IOS_PACKAGE_ROOT/scripts/pandasMesonPackages_iOS.sh"; continue ;;
		pyfftw)
			extract_ios_source pyfftw 0.15.1 bbcde6d40d165e1cbaf12dde062ebfebe9e43394cac8c166e699ba2c9a4b0461
			configure_ios_setup
			export PYFFTW_INCLUDE=$IOS_NATIVE_DIR/include PYFFTW_LIB_DIR=$IOS_NATIVE_DIR/lib PYFFTW_USE_PTHREADS=1
			export STATIC_FFTW_DIR=$IOS_NATIVE_DIR/lib
			;;
		cvxopt)
			extract_ios_source suitesparse f8ed019 9d1417f85682d39e0e7e95877ca50bbb6978dbdb494c46c2b32433fe6e356897 https://github.com/DrTimothyAldenDavis/SuiteSparse/archive/f8ed0196d35a98caacdf660ac55765915f67298d.tar.gz
			export CVXOPT_SUITESPARSE_SRC_DIR=$IOS_SOURCE_DIR
			extract_ios_source cvxopt 1.3.2 3461fa42c1b2240ba4da1d985ca73503914157fc4c77417327ed6d7d85acdbe6
			configure_ios_setup
			test -f "$IOS_NATIVE_DIR/openblas.framework/openblas"
			mkdir -p "$IOS_NATIVE_DIR/lib"
			ln -sfn ../openblas.framework/openblas "$IOS_NATIVE_DIR/lib/libopenblas.dylib"
			export CVXOPT_BLAS_LIB=openblas CVXOPT_LAPACK_LIB=openblas CVXOPT_BLAS_LIB_DIR=$IOS_NATIVE_DIR/lib CVXOPT_LAPACK_LIB_DIR=$IOS_NATIVE_DIR/lib
			export CVXOPT_BUILD_FFTW=1 CVXOPT_FFTW_LIB_DIR=$IOS_NATIVE_DIR/lib CVXOPT_FFTW_INC_DIR=$IOS_NATIVE_DIR/include
			export LDSHARED="$LDSHARED -framework openblas" LDCXXSHARED="$LDCXXSHARED -framework openblas"
			;;
		*) echo "Unsupported math package: $package" >&2; exit 1 ;;
	esac
	pushd "$IOS_SOURCE_DIR"
	run_ios_setup build --parallel 4
	copy_package_files
	case $package in
		pyfftw) install_site_package pyfftw/pyfftw build/lib.*/pyfftw/pyfftw*.so ;;
		cvxopt)
			for module in amd base blas cholmod fftw lapack misc_solvers umfpack; do
				install_site_package "cvxopt/$module" build/lib.*/cvxopt/"$module"*.so
			done ;;
	esac
	popd
done
