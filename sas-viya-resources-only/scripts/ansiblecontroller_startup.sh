#!/bin/bash
if [ -e "$HOME/.profile" ]; then
	. $HOME/.profile
fi
if [ -e "$HOME/.bash_profile" ]; then
	. $HOME/.bash_profile
fi
#set -x
#set -v
ScriptDirectory="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
environmentLocation="/sas/install/env.ini"

echo "$@" >> /tmp/commands.log
mkdir -p "/sas/install"

. "$environmentLocation"
chmod 700 "$INSTALL_DIR"
chown $INSTALL_USER "/sas/install"
set -e

if [[ -z "$SCRIPT_PHASE" ]]; then
SCRIPT_PHASE="$1"
fi

if [[ "$SCRIPT_PHASE" -eq "1" ]]; then
cat << EOF > "$environmentLocation"
export https_location="$2"
export https_sas_key="$3"
export INSTALL_USER="$4"
export azure_storage_account="${5}"
export azure_storage_files_share="${6}"
export azure_storage_files_password="${7}"

export LOGS_DIR=/var/log/sas/install
export DIRECTORY_NFS_SHARE="/mnt/\${azure_storage_files_share}"
export NFS_SHARE_DIR="/mnt/\${azure_storage_files_share}"
export INSTALL_DIR="/sas/install"
export ANSIBLE_KEY_DIR="\${DIRECTORY_NFS_SHARE}/setup/ansible_key"
export READINESS_FLAGS_DIR="\${DIRECTORY_NFS_SHARE}/setup/readiness_flags"
export DIRECTORY_ANSIBLE_INVENTORIES="\${DIRECTORY_NFS_SHARE}/setup/ansible/inventory"
export DIRECTORY_ANSIBLE_GROUPS="\${DIRECTORY_NFS_SHARE}/setup/ansible/groups"
export CODE_DIRECTORY="\${INSTALL_DIR}"
export UTILITIES_DIR="\${INSTALL_DIR}/bin"

EOF
. "$environmentLocation"

echo "running ansible prerequisites install"
${ScriptDirectory}/ansiblecontroller_prereqs.sh

fi
