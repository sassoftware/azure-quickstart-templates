#!/bin/bash
set -x
set -v
set -e

. "/sas/install/env.ini"

if [ -z "$INSTALL_USER" ]; then
	INSTALL_USER="sas"
fi


if ! type -p ansible;  then
   # install Ansible
    curl --retry 10 --max-time 60 --fail --silent --show-error "https://bootstrap.pypa.io/pip/2.7/get-pip.py" -o "get-pip.py"
    sudo python get-pip.py
    pip install 'ansible==2.9.14'
fi
yum install -y yum-utils
yum install -y java-1.8.0-openjdk

# remove the requiretty from the sudoers file. Per bug https://bugzilla.redhat.com/show_bug.cgi?id=1020147 this is unnecessary and has been removed on future releases of redhat,
# so is just a slowdown that denies pipelining and makes the non-tty session from azure extentions break on sudo without faking one (my prefered method is ssh back into the same user, but seriously..)
sed -i -e '/Defaults    requiretty/{ s/.*/# Defaults    requiretty/ }' /etc/sudoers

echo "$(date)"
echo "Creating the share on the storage account."
yum install -y rh-python36 gcc time
/opt/rh/rh-python36/root/usr/bin/pip install --upgrade pip
/opt/rh/rh-python36/root/usr/bin/pip3 install azure-cli
/opt/rh/rh-python36/root/usr/bin/az storage share create --name ${azure_storage_files_share} --connection-string "DefaultEndpointsProtocol=https;EndpointSuffix=core.windows.net;AccountName=${azure_storage_account};AccountKey=${azure_storage_files_password}"

echo "setup cifs"
cifs_server_fqdn="${azure_storage_account}.file.core.windows.net"
yum install -y cifs-utils

if [ ! -d "/etc/smbcredentials" ]; then
    sudo mkdir /etc/smbcredentials
fi
chmod 700 /etc/smbcredentials
if [ ! -f "/etc/smbcredentials/${azure_storage_account}.cred" ]; then
    echo "username=${azure_storage_account}" >> /etc/smbcredentials/${azure_storage_account}.cred
    echo "password=${azure_storage_files_password}" >> /etc/smbcredentials/${azure_storage_account}.cred
fi
chmod 600 "/etc/smbcredentials/${azure_storage_account}.cred"

mkdir -p "${DIRECTORY_NFS_SHARE}"
echo "//${cifs_server_fqdn}/${azure_storage_files_share} ${DIRECTORY_NFS_SHARE}  cifs defaults,vers=3.0,credentials=/etc/smbcredentials/${azure_storage_account}.cred,dir_mode=0777,file_mode=0777,sec=ntlmssp 0 0" >> /etc/fstab
#mount -a

mount "${DIRECTORY_NFS_SHARE}"
RET=$?
if [ "$RET" -ne "0" ]; then
    exit $RET
fi
echo "Mounting Successful"

# load the code from remote
echo "$(date)"
echo "download all files from file tree"
file_list_url="${https_location}file_tree.txt"
if [ ! -z "$https_sas_key" ]; then
	file_list_url="${file_list_url}${https_sas_key}"
fi

echo "pullin from url: $file_list_url"
curl --retry 10 --max-time 60 --fail --silent --show-error "$file_list_url" > file_list.txt
while read line; do
  file_name="$(echo "$line" | cut -f1 -d'|')"
  chmod_attr="$(echo "$line" | cut -f2 -d'|')"
  directory="$(dirname "$line")"
  target_directory="${CODE_DIRECTORY}/$directory"
  target_file_name="${CODE_DIRECTORY}/${file_name}"
  target_url="${https_location%"/"}${file_name}"
  if [ ! -z "$https_sas_key" ]; then
	target_url="${target_url}${https_sas_key}"
  fi
  mkdir -p "$target_directory"
  echo "Downloading '$target_file_name' from '$target_url'"
  curl --retry 10 --max-time 60 --fail --silent --show-error "$target_url" > "$target_file_name"
  chmod $chmod_attr "$target_file_name"
done <file_list.txt

#Now make the sharing structure
mkdir -p "${ANSIBLE_KEY_DIR}"
mkdir -p "${READINESS_FLAGS_DIR}"
mkdir -p "${DIRECTORY_ANSIBLE_INVENTORIES}"
mkdir -p "${DIRECTORY_ANSIBLE_GROUPS}"

#
# create directories
#
sudo mkdir -p ${INSTALL_DIR}
sudo chmod 755 ${INSTALL_DIR}
sudo chown ${INSTALL_USER}:${INSTALL_USER} ${INSTALL_DIR}

sudo mkdir -p ${NFS_SHARE_DIR}
sudo chmod 777 ${NFS_SHARE_DIR}  # may not need to be 777 since it should be the same user everywhere. The user may have a different UID/GUI though.
sudo chown ${INSTALL_USER}:${INSTALL_USER} ${NFS_SHARE_DIR}

sudo mkdir -p ${ANSIBLE_KEY_DIR}
sudo chmod 777 ${ANSIBLE_KEY_DIR}  # may not need to be 777 since it should be the same user everywhere. The user may have a different UID/GUI though.
sudo chown ${INSTALL_USER}:${INSTALL_USER} ${ANSIBLE_KEY_DIR}

sudo mkdir -p ${READINESS_FLAGS_DIR}
sudo chmod 777 ${READINESS_FLAGS_DIR}   # may not need to be 777 since it should be the same user everywhere. The user may have a different UID/GUI though.
sudo chown ${INSTALL_USER}:${INSTALL_USER} ${READINESS_FLAGS_DIR}

sudo mkdir -p ${LOGS_DIR}
sudo chmod 755 ${LOGS_DIR}
sudo chown ${INSTALL_USER}:${INSTALL_USER} ${LOGS_DIR}

sudo mkdir -p ${UTILITIES_DIR}
sudo chmod 755 ${UTILITIES_DIR}
sudo chown ${INSTALL_USER}:${INSTALL_USER} ${UTILITIES_DIR}

echo "$(date)"
echo "next we generate the ssh key for ansible"
# now we create the ssh key and send it over the directory.
su - ${INSTALL_USER}<<END
ssh-keygen -f /home/${INSTALL_USER}/.ssh/id_rsa -t rsa -N ''
cp /home/${INSTALL_USER}/.ssh/id_rsa.pub "${DIRECTORY_NFS_SHARE}/setup/ansible_key/id_rsa.pub"
cat "/home/${INSTALL_USER}/.ssh/id_rsa.pub" >> "/home/${INSTALL_USER}/.ssh/authorized_keys"
chmod 600 "/home/${INSTALL_USER}/.ssh/authorized_keys"
END

echo "$(date)"

if [ -e "$DIRECTORY_NFS_SHARE" ]; then
chown -R ${INSTALL_USER}:${INSTALL_USER} "$DIRECTORY_NFS_SHARE"
fi
if [ -e "$INSTALL_DIR" ]; then
chown -R ${INSTALL_USER}:${INSTALL_USER} "$INSTALL_DIR"
fi
# running ansible will have created this directory with root, so we want to change this to use by the primary user since root can still use it and later when we run as the primary user, we want to not run into permission denied.
if [ -e "/tmp/.ansible" ]; then
chown -R ${INSTALL_USER}:${INSTALL_USER} /tmp/.ansible
fi

ln -s "$NFS_SHARE_DIR" "${INSTALL_DIR}/nfs"

