#!/bin/bash
set +e
ifconfig

packer -v  # $? of "packer -v" is 1 ...
vagrant -v
set -e

echo "Modify rackhd-builds ansible role to redirect to Artifactory.."

cd $WORKSPACE/build/packer/ansible/roles/rackhd-builds/tasks
sed -i "s#https://dl.bintray.com/rackhd/debian trusty release#deb https://roebling.hwimo.lab.emc.com/artifactory/${STAGE_REPO_NAME} ${DEB_DISTRIBUTION} ${DEB_COMPONENT}#" main.yml
sed -i "s#https://dl.bintray.com/rackhd/debian trusty main#deb https://roebling.hwimo.lab.emc.com/artifactory/${STAGE_REPO_NAME} ${DEB_DISTRIBUTION} ${DEB_COMPONENT}#" main.yml
cd $WORKSPACE

echo "Modify apt ansible role to apply artifactory EMC SSL certificates.."
# Modify the default "apt-get update" ansible role as below
# to ensure the node can access the EMC Artifactory
# "apt" is the first step of the ansible roles
cat > $WORKSPACE/build/packer/ansible/roles/apt/tasks/main.yml  << EOF
---
- name: Create directory for ca certificates /usr/local/share/ca-certificates
  file: path=/usr/local/share/ca-certificates  state=directory mode=0777
  sudo: yes

- name: Copy EMC SSL files  /usr/local/share/ca-certificates/emcssl.crt
  copy: src=$EMCSSL dest=/usr/local/share/ca-certificates/emcssl.crt
  sudo: yes

- name: Copy EMC SSL Chain files /usr/local/share/ca-certificates/emcsslchain.crt
  copy: src=$EMCSSLCHAIN dest=/usr/local/share/ca-certificates/emcsslchain.crt
  sudo: yes

- name: Update CA certificates 
  shell: /usr/sbin/update-ca-certificates -v
  sudo: yes

- name: Update apt
  apt: update-cache=yes
  sudo: yes
EOF

echo "Modify rackhd-builds ansbiel roles to remove the EMC CA at the end.."

#Remove EMC CA from the ova/vagrant
# "rackhd-builds" is the last step of the ansible roles
echo "" >> $WORKSPACE/build/packer/ansible/roles/rackhd-builds/tasks/main.yml # newline
cat >> $WORKSPACE/build/packer/ansible/roles/rackhd-builds/tasks/main.yml << EOF
- name: Remove EMC CA
  shell: rm -f /usr/local/share/ca-certificates/*    ||     rm -f /etc/ssl/certs/emc*
  sudo: yes
EOF


echo "kill previous running packer instances"

set +e
pkill packer
set -e

echo "Start to packer build .."

cd ..
cd $WORKSPACE/build/packer 
#export vars to build virtualbox
export PACKER_CACHE_DIR=$HOME/.packer_cache
if [ "${IS_OFFICIAL_RELEASE}" == "true" ]; then
    export ANSIBLE_PLAYBOOK=rackhd_release
else
    export ANSIBLE_PLAYBOOK=rackhd_ci_builds
fi
export UPLOAD_BOX_TO_ATLAS=false
export RACKHD_VERSION=$RACKHD_VERSION
#export end

#build
./HWIMO-BUILD

PACKERDIR="$WORKSPACE/build/packer/"
BOX="$PACKERDIR/packer_virtualbox-iso_virtualbox.box"
if [ -e "$BOX" ]; then
  mv "$BOX" "$PACKERDIR/rackhd-${OS_VER}-${RACKHD_VERSION}.box"
fi
