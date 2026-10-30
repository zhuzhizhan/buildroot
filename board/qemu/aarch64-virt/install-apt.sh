#!/bin/sh
#
# Install a minimal apt/dpkg userland in the target rootfs and bootstrap a
# dpkg database that describes the packages already provided by Buildroot.
#
# Buildroot is not a Debian-derived system and has no apt package.  This
# script installs the aarch64 apt/dpkg packages from Ubuntu 24.04 and marks
# the Buildroot C library / toolchain components as installed so that apt
# can resolve dependencies without replacing the base system.

set -e

TARGET_DIR="$1"
BOARD_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILDROOT_DIR="$(cd "${BOARD_DIR}/../../.." && pwd)"
DEB_DIR="${BUILDROOT_DIR}/dl/apt-native"
MANIFEST="${BOARD_DIR}/apt-packages.txt"
BASE_URL="http://ports.ubuntu.com/ubuntu-ports"
DPKG_STATUS="${TARGET_DIR}/var/lib/dpkg/status"

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
		(cd "${tmpdir}" && ar x "${deb}" &&
		 tar -xf data.tar.* -C "${TARGET_DIR}")
		rm -rf "${tmpdir}"
	fi
}

add_fake_package()
{
	pkg="$1"
	version="$2"
	{
		echo "Package: ${pkg}"
		echo "Status: install ok installed"
		echo "Priority: required"
		echo "Section: libs"
		echo "Installed-Size: 0"
		echo "Maintainer: Buildroot <buildroot@localhost>"
		echo "Architecture: arm64"
		echo "Multi-Arch: same"
		echo "Version: ${version}"
		echo "Description: ${pkg} provided by Buildroot"
		echo
	} >> "${DPKG_STATUS}"
}

add_extracted_package()
{
	deb="$1"
	control_dir="$(mktemp -d)"
	dpkg-deb -e "${deb}" "${control_dir}"
	pkg="$(dpkg-deb -f "${deb}" Package)"

	{
		dpkg-deb -f "${deb}" | sed '1a Status: install ok installed'
		if [ -f "${control_dir}/conffiles" ]; then
			echo "Conffiles:"
			while read -r conf; do
				[ -n "${conf}" ] || continue
				[ -f "${TARGET_DIR}${conf}" ] || continue
				echo " ${conf} $(md5sum "${TARGET_DIR}${conf}" |
					awk '{print $1}')"
			done < "${control_dir}/conffiles"
		fi
		echo
	} >> "${DPKG_STATUS}"

	if [ -f "${control_dir}/md5sums" ]; then
		cp "${control_dir}/md5sums" \
			"${TARGET_DIR}/var/lib/dpkg/info/${pkg}.md5sums"
	fi

	dpkg-deb -c "${deb}" | awk '{print $6}' | sed 's#^\./##' |
		grep -v '^$' > "${TARGET_DIR}/var/lib/dpkg/info/${pkg}.list" ||
		true

	rm -rf "${control_dir}"
}

mkdir -p "${TARGET_DIR}/var/lib/dpkg/info" \
	 "${TARGET_DIR}/var/lib/dpkg/updates" \
	 "${TARGET_DIR}/var/lib/dpkg/parts" \
	 "${TARGET_DIR}/var/lib/dpkg/triggers" \
	 "${TARGET_DIR}/var/lib/dpkg/alternatives" \
	 "${TARGET_DIR}/var/lib/apt/lists/partial" \
	 "${TARGET_DIR}/var/cache/apt/archives/partial" \
	 "${TARGET_DIR}/var/log/apt" \
	 "${TARGET_DIR}/etc/apt/apt.conf.d" \
	 "${TARGET_DIR}/etc/apt/preferences.d" \
	 "${TARGET_DIR}/etc/apt/trusted.gpg.d" \
	 "${TARGET_DIR}/etc/apt/sources.list.d"

: > "${DPKG_STATUS}"
: > "${TARGET_DIR}/var/lib/dpkg/available"
: > "${TARGET_DIR}/var/lib/dpkg/diversions"
: > "${TARGET_DIR}/var/lib/dpkg/statoverride"
: > "${TARGET_DIR}/var/lib/dpkg/triggers/Unincorp"

# Packages provided by Buildroot, not by Ubuntu.
add_fake_package "libc6" "2.43-0"
add_fake_package "libc-bin" "2.43-0"
add_fake_package "libgcc-s1" "14.3.0-0"
add_fake_package "gcc-14-base" "14-20240412-0ubuntu1"
add_fake_package "base-passwd" "3.6.3-0"
add_fake_package "ca-certificates" "20240203"

while read -r path sha256; do
	[ -n "${path}" ] || continue
	fetch_and_extract "${path}" "${sha256}"
	add_extracted_package "${DEB_DIR}/$(basename "${path}")"
done < "${MANIFEST}"

# dpkg-deb calls tar with GNU-specific options.  Buildroot's BusyBox tar
# comes first in PATH, so point it at the GNU tar installed above.
if [ -x "${TARGET_DIR}/usr/bin/tar" ]; then
	ln -sf ../usr/bin/tar "${TARGET_DIR}/bin/tar"
fi

# Let apt run its download helpers as root and use the Buildroot libc.
cat > "${TARGET_DIR}/etc/apt/sources.list" <<'EOF'
deb http://ports.ubuntu.com/ubuntu-ports noble main universe
deb http://ports.ubuntu.com/ubuntu-ports noble-updates main universe
EOF

cat > "${TARGET_DIR}/etc/apt/apt.conf.d/99buildroot" <<'EOF'
APT::Sandbox::User "root";
Acquire::Languages "none";
Acquire::Retries "3";
DPkg::Options { "--force-confdef"; "--force-confold"; "--no-triggers"; };
EOF

# Never let apt replace the Buildroot base system libraries.
cat > "${TARGET_DIR}/etc/apt/preferences.d/99buildroot" <<'EOF'
Package: libc6 libc-bin libgcc-s1 base-passwd
Pin: version *
Pin-Priority: 1001
EOF

# apt normally creates this user in its postinst script, which we do not run.
if ! grep -q '^_apt:' "${TARGET_DIR}/etc/passwd"; then
	echo '_apt:x:999:999::/nonexistent:/bin/false' >> \
		"${TARGET_DIR}/etc/passwd"
	echo '_apt:x:999:' >> "${TARGET_DIR}/etc/group"
fi

# Do not start services while packages are configured, and provide a no-op
# ldconfig for packages that use the ldconfig trigger.
mkdir -p "${TARGET_DIR}/usr/sbin"
cat > "${TARGET_DIR}/usr/sbin/policy-rc.d" <<'EOF'
#!/bin/sh
exit 101
EOF
chmod 755 "${TARGET_DIR}/usr/sbin/policy-rc.d"

mkdir -p "${TARGET_DIR}/sbin"
cat > "${TARGET_DIR}/sbin/ldconfig" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 755 "${TARGET_DIR}/sbin/ldconfig"

chmod 644 "${DPKG_STATUS}"
