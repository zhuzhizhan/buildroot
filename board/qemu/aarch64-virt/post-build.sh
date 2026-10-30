#!/bin/sh
#
# Install a native aarch64 GCC toolchain in the target rootfs so that
# programs can be compiled directly inside the emulated system.
#
# Buildroot deliberately does not provide an on-target compiler.  We use
# the self-contained aarch64 GCC 13 packages from Ubuntu 24.04 (noble)
# and the Buildroot staging sysroot (headers, startup files, linker
# scripts) so that compiled programs link against the target glibc.

set -e

TARGET_DIR="$1"
BOARD_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILDROOT_DIR="$(cd "${BOARD_DIR}/../../.." && pwd)"
STAGING_DIR="${BUILDROOT_DIR}/output/staging"
DEB_DIR="${BUILDROOT_DIR}/dl/gcc-native"
BASE_URL="http://ports.ubuntu.com/ubuntu-ports"

fetch_and_extract()
{
	path="$1"
	sha256="$2"
	deb="${DEB_DIR}/$(basename "${path}")"

	mkdir -p "${DEB_DIR}"
	if [ ! -f "${deb}" ]; then
		echo "Downloading $(basename "${path}")"
		if command -v wget >/dev/null 2>&1; then
			wget -q -O "${deb}.tmp" "${BASE_URL}/${path}" &&
				mv "${deb}.tmp" "${deb}"
		else
			curl -fsSL -o "${deb}.tmp" "${BASE_URL}/${path}" &&
				mv "${deb}.tmp" "${deb}"
		fi
	fi

	echo "${sha256}  ${deb}" | sha256sum -c - >/dev/null

	if command -v dpkg-deb >/dev/null 2>&1; then
		dpkg-deb -x "${deb}" "${TARGET_DIR}"
	else
		tmpdir="$(mktemp -d)"
		(cd "${tmpdir}" && ar x "${deb}" && tar -xf data.tar.* -C "${TARGET_DIR}")
		rm -rf "${tmpdir}"
	fi
}

while read -r path sha256; do
	[ -n "${path}" ] || continue
	fetch_and_extract "${path}" "${sha256}"
done <<EOF
pool/main/g/gcc-13/gcc-13-aarch64-linux-gnu_13.2.0-23ubuntu4_arm64.deb afa768e7a0349c8dc1e0c43a2675ede405f097b6fd55f7188027470c4812dd8a
pool/main/g/gcc-13/cpp-13-aarch64-linux-gnu_13.2.0-23ubuntu4_arm64.deb b8062c2e37b8b44fd1cbfc193d2943761e1bd02e32dd0b47bea5ff860fcb4dcb
pool/main/g/gcc-13/gcc-13-base_13.2.0-23ubuntu4_arm64.deb fe2c21057a9f9a02d4fec5c646280f51eb1063e84802a83e70b6184a68182512
pool/main/g/gcc-13/libgcc-13-dev_13.2.0-23ubuntu4_arm64.deb f8faa5fee7174ec5fdd3eecbc27f38d530f7b500ad6763e2b57a9ac88622dc37
pool/main/g/gmp/libgmp10_6.3.0+dfsg-2ubuntu6_arm64.deb 8b09803a6318428836ed522f8891edb2a7cf3197433d6aa1bbdedcd07d4124db
pool/main/m/mpfr4/libmpfr6_4.2.1-1build1_arm64.deb 27d4a76723a77bfaa7c8035907bddf5d9c573d36165c476935f88c30e2fddee5
pool/main/m/mpclib3/libmpc3_1.3.1-1build1_arm64.deb cf8e14c8157fefbe33e63c87bd1810e716f4184d950ea620ec17be547aeb614f
pool/main/i/isl/libisl23_0.26-3build1_arm64.deb a65efa480539f8792960d24a02b7dcffd34c3ef9610660d7953d82ee1e8560f4
pool/main/libz/libzstd/libzstd1_1.5.5+dfsg2-2build1_arm64.deb 98568129024af1a71702d5a13f2e01c53afd5e2c3f71b2ee97fdd9a19cd97eda
pool/main/z/zlib/zlib1g_1.3.dfsg-3.1ubuntu2_arm64.deb 66aaebb68401a88b4f70a5f48e1a516b611fdcaae15208d8aee677c556d2cf01
EOF

# Buildroot removes development files from the target; restore the ones
# matching the target C library for on-target compilation.
if [ -d "${STAGING_DIR}/usr/include" ]; then
	cp -a "${STAGING_DIR}/usr/include/." "${TARGET_DIR}/usr/include/"
fi
if [ -d "${STAGING_DIR}/usr/lib" ]; then
	cp -a "${STAGING_DIR}/usr/lib/." "${TARGET_DIR}/usr/lib/"
fi
if [ -d "${STAGING_DIR}/lib" ]; then
	cp -a "${STAGING_DIR}/lib/." "${TARGET_DIR}/lib/"
fi

# Install apt/dpkg and bootstrap a dpkg database describing the packages
# already provided by Buildroot.
"${BOARD_DIR}/install-apt.sh" "${TARGET_DIR}"

# The Ubuntu libraries are installed under the multiarch directory.  Make
# them visible through the default /usr/lib search path.
for src in "${TARGET_DIR}/usr/lib/aarch64-linux-gnu/"*; do
	[ -e "${src}" ] || continue
	name="$(basename "${src}")"
	dst="${TARGET_DIR}/usr/lib/${name}"
	if [ -e "${dst}" ] && \
	   [ "$(readlink -f "${src}")" = "$(readlink -f "${dst}")" ]; then
		continue
	fi
	cp -a "${src}" "${TARGET_DIR}/usr/lib/"
done

# Help GCC find the C library files under the multiarch path it uses by
# default.
mkdir -p "${TARGET_DIR}/usr/lib/aarch64-linux-gnu"
for f in crt1.o Scrt1.o gcrt1.o grcrt1.o Mcrt1.o rcrt1.o crti.o crtn.o \
	 libc.so libc_nonshared.a libm.so libmvec.so libpthread.so libdl.so \
	 librt.so libresolv.so libutil.so libanl.so libBrokenLocale.so \
	 libthread_db.so; do
	if [ -e "${TARGET_DIR}/usr/lib/${f}" ] && \
	   [ ! -e "${TARGET_DIR}/usr/lib/aarch64-linux-gnu/${f}" ]; then
		ln -s "../${f}" "${TARGET_DIR}/usr/lib/aarch64-linux-gnu/${f}"
	fi
done
if [ -e "${TARGET_DIR}/lib/libgcc_s.so.1" ] && \
   [ ! -e "${TARGET_DIR}/usr/lib/libgcc_s.so.1" ]; then
	ln -s "../../lib/libgcc_s.so.1" "${TARGET_DIR}/usr/lib/libgcc_s.so.1"
fi

# The Ubuntu GCC driver uses the aarch64-linux-gnu- tool prefix.  The
# target binutils built by Buildroot may use a different prefix, so make
# sure both names are available.
for tool in as ld ld.bfd ar nm objcopy objdump ranlib readelf strip; do
	src=""
	for candidate in "${TARGET_DIR}/usr/bin/${tool}" \
			 "${TARGET_DIR}/usr/bin/aarch64-buildroot-linux-gnu-${tool}" \
			 "${TARGET_DIR}/usr/bin/aarch64-linux-gnu-${tool}"; do
		if [ -f "${candidate}" ] && [ ! -L "${candidate}" ]; then
			src="$(basename "${candidate}")"
			break
		fi
	done
	[ -n "${src}" ] || continue
	for link in "${tool}" "aarch64-linux-gnu-${tool}" \
		    "aarch64-buildroot-linux-gnu-${tool}"; do
		if [ ! -e "${TARGET_DIR}/usr/bin/${link}" ]; then
			ln -s "${src}" "${TARGET_DIR}/usr/bin/${link}"
		fi
	done
done

# Provide the usual compiler command names.
ln -sf aarch64-linux-gnu-gcc-13 "${TARGET_DIR}/usr/bin/gcc"
ln -sf aarch64-linux-gnu-gcc-13 "${TARGET_DIR}/usr/bin/gcc-13"
ln -sf aarch64-linux-gnu-cpp-13 "${TARGET_DIR}/usr/bin/cpp"
ln -sf gcc "${TARGET_DIR}/usr/bin/cc"

if [ ! -x "${TARGET_DIR}/usr/bin/aarch64-linux-gnu-gcc-13" ] || \
   [ ! -x "${TARGET_DIR}/usr/libexec/gcc/aarch64-linux-gnu/13/cc1" ]; then
	echo "ERROR: native GCC installation is incomplete" >&2
	exit 1
fi

# Drop symlinks for optional runtime libraries we do not install.
find "${TARGET_DIR}/usr/lib/gcc" -xtype l -delete 2>/dev/null || true

# Do not ship documentation from the prebuilt packages.
rm -rf "${TARGET_DIR}/usr/share/doc" "${TARGET_DIR}/usr/share/man" \
       "${TARGET_DIR}/usr/share/info" "${TARGET_DIR}/usr/share/lintian"
