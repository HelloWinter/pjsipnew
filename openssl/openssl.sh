#!/bin/sh

#  Automatic build script for libssl and libcrypto
#  for iPhoneOS, iPhoneSimulator, macOS, tvOS and watchOS
#
#  Created by Felix Schulze on 16.12.10.
#  Copyright 2010-2017 Felix Schulze. All rights reserved.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#

# -u  Attempt to use undefined variable outputs error message, and forces an exit
set -u

# SCRIPT DEFAULTS

# Default version in case no version is specified
DEFAULTVERSION="1.1.0i"

# Default (=full) set of architectures (OpenSSL <= 1.0.2) or targets (OpenSSL >= 1.1.0) to build
#DEFAULTARCHS="ios_x86_64 ios_arm64 ios_armv7s ios_armv7 tv_x86_64 tv_arm64 mac_x86_64"
#DEFAULTTARGETS="ios-sim-cross-x86_64 ios64-cross-arm64 ios-cross-armv7s ios-cross-armv7 tvos-sim-cross-x86_64 tvos64-cross-arm64 macos64-x86_64"
DEFAULTARCHS="ios_x86_64 ios_arm64 tv_x86_64 tv_arm64 mac_x86_64 watchos_armv7k watchos-arm64_32"
#DEFAULTTARGETS="ios-sim-cross-x86_64 ios64-cross-arm64 tvos-sim-cross-x86_64 tvos64-cross-arm64 macos64-x86_64 watchos-cross-armv7k watchos-cross-arm64_32"
DEFAULTTARGETS="ios-sim-cross-i386 ios-sim-cross-x86_64 ios64-cross-arm64 ios-cross-armv7 ios-cross-armv7s macos64-x86_64" # only targeting macOS and iOS for integration with pjsip (do we really need i386???)

# Init optional env variables (use available variable or default to empty string)
CURL_OPTIONS="${CURL_OPTIONS:-}"
CONFIG_OPTIONS="${CONFIG_OPTIONS:-}"

echo_help()
{
  echo "Usage: $0 [options...]"
  echo "Generic options"
  echo "     --branch=BRANCH               Select OpenSSL branch to build. The script will determine and download the latest release for that branch"
  echo "     --cleanup                     Clean up build directories (bin, include/openssl, lib, src) before starting build"
  echo "     --ec-nistp-64-gcc-128         Enable configure option enable-ec_nistp_64_gcc_128 for 64 bit builds"
  echo " -h, --help                        Print help (this message)"
  echo "     --macos-sdk=SDKVERSION        Override macOS SDK version"
  echo "	   --macos-min-sdk=SDKVERSION	 Override macOS minimum SDK version"
  echo "     --ios-sdk=SDKVERSION          Override iOS SDK version"
  echo "	   --ios-min-sdk=SDKVERSION	 	 Override iOS minimum SDK version"
  echo "     --noparallel                  Disable running make with parallel jobs (make -j)"
  echo "	   --reporoot					 Specify repository root directory of openssl"
  echo "     --tvos-sdk=SDKVERSION         Override tvOS SDK version"
  echo "     --disable-bitcode             Disable embedding Bitcode"
  echo " -v, --verbose                     Enable verbose logging"
  echo "     --verbose-on-error            Dump last 500 lines from log file if an error occurs (for Travis builds)"
  echo "     --version=VERSION             OpenSSL version to build (defaults to ${DEFAULTVERSION})"
  echo
  echo "Options for OpenSSL 1.0.2 and lower ONLY"
  echo "     --archs=\"ARCH ARCH ...\"       Space-separated list of architectures to build"
  echo "                                     Options: ${DEFAULTARCHS}"
  echo
  echo "Options for OpenSSL 1.1.0 and higher ONLY"
  echo "     --deprecated                  Exclude no-deprecated configure option and build with deprecated methods"
  echo "     --targets=\"TARGET TARGET ...\" Space-separated list of build targets"
  echo "                                     Options: ${DEFAULTTARGETS}"
  echo
  echo "For custom configure options, set variable CONFIG_OPTIONS"
  echo "For custom cURL options, set variable CURL_OPTIONS"
  echo "  Example: CURL_OPTIONS=\"--proxy 192.168.1.1:8080\" ./build-libssl.sh"
}

spinner()
{
  local pid=$!
  local delay=0.75
  local spinstr='|/-\'
  while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
    local temp=${spinstr#?}
    printf "  [%c]" "$spinstr"
    local spinstr=$temp${spinstr%"$temp"}
    sleep $delay
    printf "\b\b\b\b\b"
  done

  wait $pid
  return $?
}

# Prepare target and source dir in build loop
prepare_target_source_dirs()
{
  # Prepare target dir
  TARGETDIR="${CURRENTPATH}/bin/${PLATFORM}${SDKVERSION}-${ARCH}.sdk"
  mkdir -p "${TARGETDIR}"
  LOG="${TARGETDIR}/build-openssl-${VERSION}.log"

  echo "Building openssl-${VERSION} for ${PLATFORM} ${SDKVERSION} ${ARCH}..."
  echo "  Logfile: ${LOG}"

  # Prepare source dir
  SOURCEDIR="${CURRENTPATH}/src/${PLATFORM}-${ARCH}"
  mkdir -p "${SOURCEDIR}"
  tar zxf "${CURRENTPATH}/${OPENSSL_ARCHIVE_FILE_NAME}" -C "${SOURCEDIR}"
  cd "${SOURCEDIR}/${OPENSSL_ARCHIVE_BASE_NAME}"
  chmod u+x ./Configure
}

# Check for error status
check_status()
{
  local STATUS=$1
  local COMMAND=$2

  if [ "${STATUS}" != 0 ]; then
    if [[ "${LOG_VERBOSE}" != "verbose"* ]]; then
      echo "Problem during ${COMMAND} - Please check ${LOG}"
    fi

    # Dump last 500 lines from log file for verbose-on-error
    if [ "${LOG_VERBOSE}" == "verbose-on-error" ]; then
      echo "Problem during ${COMMAND} - Dumping last 500 lines from log file"
      echo
      tail -n 500 "${LOG}"
    fi

    exit 1
  fi
}

# Run Configure in build loop
run_configure()
{
  echo "  Configure..."
  set +e
  if [ "${LOG_VERBOSE}" == "verbose" ]; then
    ./Configure ${LOCAL_CONFIG_OPTIONS} | tee "${LOG}"
  else
    (./Configure ${LOCAL_CONFIG_OPTIONS} > "${LOG}" 2>&1) & spinner
  fi

  # Check for error status
  check_status $? "Configure"
}

# Run make in build loop
run_make()
{
  echo "  Make (using ${BUILD_THREADS} thread(s))..."
  if [ "${LOG_VERBOSE}" == "verbose" ]; then
    make -j "${BUILD_THREADS}" | tee -a "${LOG}"
  else
    (make -j "${BUILD_THREADS}" >> "${LOG}" 2>&1) & spinner
  fi

  # Check for error status
  check_status $? "make"
}

# Cleanup and bookkeeping at end of build loop
finish_build_loop()
{
  # Return to ${CURRENTPATH} and remove source dir
  cd "${CURRENTPATH}"
  rm -r "${SOURCEDIR}"

  # Add references to library files to relevant arrays
  if [[ "${PLATFORM}" == AppleTV* ]]; then
    LIBSSL_TVOS+=("${TARGETDIR}/lib/libssl.a")
    LIBCRYPTO_TVOS+=("${TARGETDIR}/lib/libcrypto.a")
    OPENSSLCONF_SUFFIX="tvos_${ARCH}"
  elif [[ "${PLATFORM}" == WatchOS* ]]; then
    LIBSSL_WATCHOS+=("${TARGETDIR}/lib/libssl.a")
    LIBCRYPTO_WATCHOS+=("${TARGETDIR}/lib/libcrypto.a")
    OPENSSLCONF_SUFFIX="watchos_${ARCH}"
  elif [[ "${PLATFORM}" == iPhone* ]]; then
    echo "[DEBUG] [INFO] [NOTICE]: ${TARGETDIR}/lib/libcrypto.a"
    LIBSSL_IOS+=("${TARGETDIR}/lib/libssl.a")
    LIBCRYPTO_IOS+=("${TARGETDIR}/lib/libcrypto.a")
    OPENSSLCONF_SUFFIX="ios_${ARCH}"
  else
    LIBSSL_MACOS+=("${TARGETDIR}/lib/libssl.a")
    LIBCRYPTO_MACOS+=("${TARGETDIR}/lib/libcrypto.a")
    OPENSSLCONF_SUFFIX="macos_${ARCH}"
  fi

  # Copy opensslconf.h to bin directory and add to array
  OPENSSLCONF="opensslconf_${OPENSSLCONF_SUFFIX}.h"
  cp "${TARGETDIR}/include/openssl/opensslconf.h" "${CURRENTPATH}/bin/${OPENSSLCONF}"
  OPENSSLCONF_ALL+=("${OPENSSLCONF}")

  # Keep reference to first build target for include file
  if [ -z "${INCLUDE_DIR}" ]; then
    INCLUDE_DIR="${TARGETDIR}/include/openssl"
  fi
}

# Init optional command line vars
ARCHS=""
BRANCH=""
CLEANUP=""
CONFIG_ENABLE_EC_NISTP_64_GCC_128=""
CONFIG_DISABLE_BITCODE=""
CONFIG_NO_DEPRECATED=""
MACOS_SDKVERSION=""
IOS_SDKVERSION=""
WATCHOS_SDKVERSION=""
LOG_VERBOSE=""
PARALLEL=""
TARGETS=""
TVOS_SDKVERSION=""
VERSION=""
REPOROOT=$(pwd)

# Process command line arguments
for i in "$@"
do
case $i in
  --archs=*)
    ARCHS="${i#*=}"
    shift
    ;;
  --branch=*)
    BRANCH="${i#*=}"
    shift
    ;;
  --cleanup)
    CLEANUP="true"
    ;;
  --deprecated)
    CONFIG_NO_DEPRECATED="false"
    ;;
  --ec-nistp-64-gcc-128)
    CONFIG_ENABLE_EC_NISTP_64_GCC_128="true"
    ;;
  --disable-bitcode)
    CONFIG_DISABLE_BITCODE="true"
    ;;
  -h|--help)
    echo_help
    exit
    ;;
  --macos-sdk=*)
    MACOS_SDKVERSION="${i#*=}"
    shift
    ;;
  --macos-min-sdk=*)
    MACOS_MIN_SDK_VERSION="${i#*=}"
    shift
    ;;
  --ios-sdk=*)
    IOS_SDKVERSION="${i#*=}"
    shift
    ;;
  --ios-min-sdk=*)
    IOS_MIN_SDK_VERSION="${i#*=}"
    shift
    ;;
  --noparallel)
    PARALLEL="false"
    ;;
  --targets=*)
    TARGETS="${i#*=}"
    shift
    ;;
  --tvos-sdk=*)
    TVOS_SDKVERSION="${i#*=}"
    shift
    ;;
  --watchos-sdk=*)
    WATCHOS_SDKVERSION="${i#*=}"
    shift
    ;;
  -v|--verbose)
    LOG_VERBOSE="verbose"
    ;;
  --verbose-on-error)
    LOG_VERBOSE="verbose-on-error"
    ;;
  --version=*)
    VERSION="${i#*=}"
    shift
    ;;
  --reporoot=*)
    REPOROOT="${i#*=}"
    shift
    ;;
  *)
    echo "Unknown argument: ${i}"
    ;;
esac
done

# Don't mix version and branch
if [[ -n "${VERSION}" && -n "${BRANCH}" ]]; then
  echo "Either select a branch (the script will determine and build the latest version) or select a specific version, but not both."
  exit 1

# Specific version: Verify version number format. Expected: dot notation
elif [[ -n "${VERSION}" && ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+[a-z]*$ ]]; then
  echo "Unknown version number format. Examples: 1.0.2, 1.0.2h"
  exit 1

# Specific branch
elif [ -n "${BRANCH}" ]; then
  # Verify version number format. Expected: dot notation
  if [[ ! "${BRANCH}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Unknown branch version number format. Examples: 1.0.2, 1.1.0"
    exit 1

  # Valid version number, determine latest version
  else
    echo "Checking latest version of ${BRANCH} branch on openssl.org..."
    # Get directory content listing of /source/ (only contains latest version per branch), limit list to archives (so one archive per branch),
    # filter for the requested branch, sort the list and get the last item (last two steps to ensure there is always 1 result)
    VERSION=$(curl ${CURL_OPTIONS} -s https://ftp.openssl.org/source/ | grep -Eo '>openssl-[0-9]\.[0-9]\.[0-9][a-z]*\.tar\.gz<' | grep -Eo "${BRANCH//./\.}[a-z]*" | sort | tail -1)

    # Verify result
    if [ -z "${VERSION}" ]; then
      echo "Could not determine latest version, please check https://www.openssl.org/source/ and use --version option"
      exit 1
    fi
  fi

# Script default
elif [ -z "${VERSION}" ]; then
  VERSION="${DEFAULTVERSION}"
fi

# Build type:
# In short, type "archs" is used for OpenSSL versions in the 1.0 branch and type "targets" for later versions.
#
# Significant changes to the build process were introduced with OpenSSL 1.1.0. As a result, this script was updated
# to include two separate build loops for versions <= 1.0 and versions >= 1.1. The type "archs" matches the key variable
# used to determine for which platforms to build for the 1.0 branch. Since 1.1, all platforms are defined in a separate/
# custom configuration file as build targets. Therefore the key variable and type are called targets for 1.1 (and later).

# OpenSSL branches <= 1.0
if [[ "${VERSION}" =~ ^(0\.9|1\.0) ]]; then
  BUILD_TYPE="archs"

  # Set default for ARCHS if not specified
  if [ ! -n "${ARCHS}" ]; then
    ARCHS="${DEFAULTARCHS}"
  fi

# OpenSSL branches >= 1.1
else
  BUILD_TYPE="targets"

  # Set default for TARGETS if not specified
  if [ ! -n "${TARGETS}" ]; then
    TARGETS="${DEFAULTTARGETS}"
  fi

  # Add no-deprecated config option (if not overwritten)
  if [ "${CONFIG_NO_DEPRECATED}" != "false" ]; then
    CONFIG_OPTIONS="${CONFIG_OPTIONS} no-deprecated"
  fi
fi

# Determine SDK versions
if [ ! -n "${MACOS_SDKVERSION}" ]; then
  MACOS_SDKVERSION=$(xcrun -sdk macosx --show-sdk-version)
fi
if [ ! -n "${IOS_SDKVERSION}" ]; then
  IOS_SDKVERSION=$(xcrun -sdk iphoneos --show-sdk-version)
fi
if [ ! -n "${TVOS_SDKVERSION}" ]; then
  TVOS_SDKVERSION=$(xcrun -sdk appletvos --show-sdk-version)
fi
if [ ! -n "${WATCHOS_SDKVERSION}" ]; then
  WATCHOS_SDKVERSION=$(xcrun -sdk watchos --show-sdk-version)
fi

# Determine number of cores for (parallel) build
BUILD_THREADS=1
if [ "${PARALLEL}" != "false" ]; then
  BUILD_THREADS=$(sysctl hw.ncpu | awk '{print $2}')
fi

# Determine script directory
SCRIPTDIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd)

# Write files relative to current location and validate directory
CURRENTPATH=$REPOROOT
case "${CURRENTPATH}" in
  *\ * )
    echo "Your path contains whitespaces, which is not supported by 'make install'."
    exit 1
  ;;
esac
cd "${CURRENTPATH}"

# Validate Xcode Developer path
DEVELOPER=$(xcode-select -print-path)
if [ ! -d "${DEVELOPER}" ]; then
  echo "Xcode path is not set correctly ${DEVELOPER} does not exist"
  echo "run"
  echo "sudo xcode-select -switch <Xcode path>"
  echo "for default installation:"
  echo "sudo xcode-select -switch /Applications/Xcode.app/Contents/Developer"
  exit 1
fi

case "${DEVELOPER}" in
  *\ * )
    echo "Your Xcode path contains whitespaces, which is not supported."
    exit 1
  ;;
esac

# Show build options
echo
echo "Build options"
echo "  OpenSSL version: ${VERSION}"
if [ "${BUILD_TYPE}" == "archs" ]; then
  echo "  Architectures: ${ARCHS}"
else
  echo "  Targets: ${TARGETS}"
fi
echo "  macOS SDK: ${MACOS_SDKVERSION}"
echo "  iOS SDK: ${IOS_SDKVERSION}"
echo "  tvOS SDK: ${TVOS_SDKVERSION}"
echo "  watchOS SDK: ${WATCHOS_SDKVERSION}"
if [ "${CONFIG_DISABLE_BITCODE}" == "true" ]; then
  echo "  Bitcode embedding disabled"
fi
echo "  Number of make threads: ${BUILD_THREADS}"
if [ -n "${CONFIG_OPTIONS}" ]; then
  echo "  Configure options: ${CONFIG_OPTIONS}"
fi
echo "  Build location: ${CURRENTPATH}"
echo

# Download OpenSSL when not present
OPENSSL_ARCHIVE_BASE_NAME="openssl-${VERSION}"
OPENSSL_ARCHIVE_FILE_NAME="${OPENSSL_ARCHIVE_BASE_NAME}.tar.gz"
if [ ! -e ${OPENSSL_ARCHIVE_FILE_NAME} ]; then
  echo "Downloading ${OPENSSL_ARCHIVE_FILE_NAME}..."
  OPENSSL_ARCHIVE_URL="https://www.openssl.org/source/${OPENSSL_ARCHIVE_FILE_NAME}"

  # Check whether file exists here (this is the location of the latest version for each branch)
  # -s be silent, -f return non-zero exit status on failure, -I get header (do not download)
  curl ${CURL_OPTIONS} -sfI "${OPENSSL_ARCHIVE_URL}" > /dev/null

  # If unsuccessful, try the archive
  if [ $? -ne 0 ]; then
    BRANCH=$(echo "${VERSION}" | grep -Eo '^[0-9]\.[0-9]\.[0-9]')
    OPENSSL_ARCHIVE_URL="https://www.openssl.org/source/old/${BRANCH}/${OPENSSL_ARCHIVE_FILE_NAME}"

    curl ${CURL_OPTIONS} -sfI "${OPENSSL_ARCHIVE_URL}" > /dev/null
  fi

  # Both attempts failed, so report the error
  if [ $? -ne 0 ]; then
    echo "An error occurred trying to find OpenSSL ${VERSION} on ${OPENSSL_ARCHIVE_URL}"
    echo "Please verify that the version you are trying to build exists, check cURL's error message and/or your network connection."
    exit 1
  fi

  # Archive was found, so proceed with download.
  # -O Use server-specified filename for download
  curl ${CURL_OPTIONS} -O "${OPENSSL_ARCHIVE_URL}"

else
  echo "Using ${OPENSSL_ARCHIVE_FILE_NAME}"
fi

# Set reference to custom configuration (OpenSSL 1.1.0)
# See: https://github.com/openssl/openssl/commit/afce395cba521e395e6eecdaf9589105f61e4411
export OPENSSL_LOCAL_CONFIG_DIR="${SCRIPTDIR}/config"

# -e  Abort script at first error, when a command exits with non-zero status (except in until or while loops, if-tests, list constructs)
# -o pipefail  Causes a pipeline to return the exit status of the last command in the pipe that returned a non-zero return value
set -eo pipefail

# Clean up target directories if requested and present
if [ "${CLEANUP}" == "true" ]; then
  if [ -d "${CURRENTPATH}/bin" ]; then
    rm -r "${CURRENTPATH}/bin"
  fi
  if [ -d "${CURRENTPATH}/include/openssl" ]; then
    rm -r "${CURRENTPATH}/include/openssl"
  fi
  if [ -d "${CURRENTPATH}/lib" ]; then
    rm -r "${CURRENTPATH}/lib"
  fi
  if [ -d "${CURRENTPATH}/src" ]; then
    rm -r "${CURRENTPATH}/src"
  fi
fi

# (Re-)create target directories
mkdir -p "${CURRENTPATH}/bin"
mkdir -p "${CURRENTPATH}/lib"
mkdir -p "${CURRENTPATH}/src"

# Init vars for library references
INCLUDE_DIR=""
OPENSSLCONF_ALL=()
LIBSSL_MACOS=()
LIBCRYPTO_MACOS=()
LIBSSL_IOS=()
LIBCRYPTO_IOS=()
LIBSSL_TVOS=()
LIBCRYPTO_TVOS=()
LIBSSL_WATCHOS=()
LIBCRYPTO_WATCHOS=()

# Run relevant build loop (archs = 1.0 style, targets = 1.1 style)
if [ "${BUILD_TYPE}" == "archs" ]; then
  source "${SCRIPTDIR}/scripts/build-loop-archs.sh"
else
  source "${SCRIPTDIR}/scripts/build-loop-targets.sh"
fi

# Build macOS library if selected for build
if [ ${#LIBSSL_MACOS[@]} -gt 0 ]; then
  echo "Build library for macOS..."
  mkdir -p "${CURRENTPATH}/lib/macos"
  lipo -create ${LIBSSL_MACOS[@]} -output "${CURRENTPATH}/lib/macos/libssl.a"
  lipo -create ${LIBCRYPTO_MACOS[@]} -output "${CURRENTPATH}/lib/macos/libcrypto.a"
fi

# Build iOS library if selected for build
if [ ${#LIBSSL_IOS[@]} -gt 0 ]; then
  echo "Build library for iOS..."
  mkdir -p "${CURRENTPATH}/lib/ios"
  lipo -create ${LIBSSL_IOS[@]} -output "${CURRENTPATH}/lib/ios/libssl.a"
  lipo -create ${LIBCRYPTO_IOS[@]} -output "${CURRENTPATH}/lib/ios/libcrypto.a"
fi

# Build tvOS library if selected for build
if [ ${#LIBSSL_TVOS[@]} -gt 0 ]; then
  echo "Build library for tvOS..."
  mkdir -p "${CURRENTPATH}/lib/tvos"
  lipo -create ${LIBSSL_TVOS[@]} -output "${CURRENTPATH}/lib/tvos/libssl.a"
  lipo -create ${LIBCRYPTO_TVOS[@]} -output "${CURRENTPATH}/lib/tvos/libcrypto.a"
fi

# Build tvOS library if selected for build
if [ ${#LIBSSL_WATCHOS[@]} -gt 0 ]; then
  echo "Build library for watchOS..."
  mkdir -p "${CURRENTPATH}/lib/watchos"
  lipo -create ${LIBSSL_WATCHOS[@]} -output "${CURRENTPATH}/lib/watchos/libssl.a"
  lipo -create ${LIBCRYPTO_WATCHOS[@]} -output "${CURRENTPATH}/lib/watchos/libcrypto.a"
fi

# Copy include directory
echo "[DEBUG] include dir: ${INCLUDE_DIR}"
echo "[DEBUG] include dir: ${CURRENTPATH}"
mkdir -p "${CURRENTPATH}/include/openssl/"
cp -R "${INCLUDE_DIR}/" "${CURRENTPATH}/include/openssl/"

# Only create intermediate file when building for multiple targets
# For a single target, opensslconf.h is still present in $INCLUDE_DIR (and has just been copied to the target include dir)
if [ ${#OPENSSLCONF_ALL[@]} -gt 1 ]; then

  # Prepare intermediate header file
  # This overwrites opensslconf.h that was copied from $INCLUDE_DIR
  OPENSSLCONF_INTERMEDIATE="${CURRENTPATH}/include/openssl/opensslconf.h"
  cp "${CURRENTPATH}/include/opensslconf-template.h" "${OPENSSLCONF_INTERMEDIATE}"

  # Loop all header files
  LOOPCOUNT=0
  for OPENSSLCONF_CURRENT in "${OPENSSLCONF_ALL[@]}" ; do

    # Copy specific opensslconf file to include dir
    cp "${CURRENTPATH}/bin/${OPENSSLCONF_CURRENT}" "${CURRENTPATH}/include/openssl"

    # Determine define condition
    case "${OPENSSLCONF_CURRENT}" in
      *_macos_x86_64.h)
        DEFINE_CONDITION="TARGET_OS_OSX && TARGET_CPU_X86_64"
      ;;
      *_macos_i386.h)
        DEFINE_CONDITION="TARGET_OS_OSX && TARGET_CPU_X86"
      ;;
      *_ios_x86_64.h)
        DEFINE_CONDITION="TARGET_OS_IOS && TARGET_OS_SIMULATOR && TARGET_CPU_X86_64"
      ;;
      *_ios_i386.h)
        DEFINE_CONDITION="TARGET_OS_IOS && TARGET_OS_SIMULATOR && TARGET_CPU_X86"
      ;;
      *_ios_arm64.h)
        DEFINE_CONDITION="TARGET_OS_IOS && TARGET_OS_EMBEDDED && TARGET_CPU_ARM64"
      ;;
      *_ios_armv7s.h)
        DEFINE_CONDITION="TARGET_OS_IOS && TARGET_OS_EMBEDDED && TARGET_CPU_ARM && defined(__ARM_ARCH_7S__)"
      ;;
      *_ios_armv7.h)
        DEFINE_CONDITION="TARGET_OS_IOS && TARGET_OS_EMBEDDED && TARGET_CPU_ARM && !defined(__ARM_ARCH_7S__)"
      ;;
      *_tvos_x86_64.h)
        DEFINE_CONDITION="TARGET_OS_TV && TARGET_OS_SIMULATOR && TARGET_CPU_X86_64"
      ;;
      *_tvos_arm64.h)
        DEFINE_CONDITION="TARGET_OS_TV && TARGET_OS_EMBEDDED && TARGET_CPU_ARM64"
      ;;
      *_watchos_armv7k.h)
        DEFINE_CONDITION="TARGET_OS_WATCHOS && TARGET_OS_EMBEDDED && TARGET_CPU_ARMV7K"
      ;;
      *_watchos_arm64_32.h)
        DEFINE_CONDITION="TARGET_OS_WATCHOS && TARGET_OS_EMBEDDED && TARGET_CPU_ARM64_32"
      ;;
      *)
        # Don't run into unexpected cases by setting the default condition to false
        DEFINE_CONDITION="0"
      ;;
    esac

    # Determine loopcount; start with if and continue with elif
    LOOPCOUNT=$((LOOPCOUNT + 1))
    if [ ${LOOPCOUNT} -eq 1 ]; then
      echo "#if ${DEFINE_CONDITION}" >> "${OPENSSLCONF_INTERMEDIATE}"
    else
      echo "#elif ${DEFINE_CONDITION}" >> "${OPENSSLCONF_INTERMEDIATE}"
    fi

    # Add include
    echo "# include <openssl/${OPENSSLCONF_CURRENT}>" >> "${OPENSSLCONF_INTERMEDIATE}"
  done

  # Finish
  echo "#else" >> "${OPENSSLCONF_INTERMEDIATE}"
  echo '# error Unable to determine target or target not included in OpenSSL build' >> "${OPENSSLCONF_INTERMEDIATE}"
  echo "#endif" >> "${OPENSSLCONF_INTERMEDIATE}"
fi

echo "Done."
