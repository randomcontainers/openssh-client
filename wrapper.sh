#!/bin/sh
# ssh, scp, sftp, ssh-add, ssh-agent, ssh-keygen and ssh-keyscan in
# /usr/local/bin are links to this script.
#
# OpenSSH refuses to start when the UID it runs as has no entry in
# /etc/passwd, which is the case for most UIDs given with docker run --user.
# For such a UID, this script writes a copy of /etc/passwd with an entry for
# it (user name ssh, home /home/ssh) to a temporary file and preloads
# nss_wrapper, which answers passwd lookups from that file. Programs started
# by the tool, such as ssh started by scp, inherit the setting.
set -eu

real="/usr/local/libexec/openssh/bin/${0##*/}"
if [ ! -x "$real" ]; then
	echo "${0##*/}: start this script through a link in /usr/local/bin" >&2
	exit 1
fi

uid="$(id -u)"
if ! getent passwd "$uid" > /dev/null 2>&1; then
	passwd="$(mktemp "${TMPDIR:-/tmp}/passwd.XXXXXX")"
	{
		cat /etc/passwd
		printf 'ssh:x:%s:%s::/home/ssh:/bin/sh\n' "$uid" "$(id -g)"
	} > "$passwd"
	NSS_WRAPPER_PASSWD="$passwd"
	NSS_WRAPPER_GROUP=/etc/group
	LD_PRELOAD="libnss_wrapper.so${LD_PRELOAD:+ $LD_PRELOAD}"
	export NSS_WRAPPER_PASSWD NSS_WRAPPER_GROUP LD_PRELOAD
fi

exec "$real" "$@"
