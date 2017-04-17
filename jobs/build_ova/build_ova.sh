#!/bin/bash
set +e
#sudo cp ${HOME}/bin/packer   /usr/bin
#sudo apt-get install -y  jq

cd $WORKSPACE/build/packer/ansible/roles/rackhd-builds/tasks
sed -i "s#https://dl.bintray.com/rackhd/debian trusty release#deb https://roebling.hwimo.lab.emc.com/artifactory/${STAGE_REPO_NAME} ${DEB_DISTRIBUTION} ${DEB_COMPONENT}#" main.yml
sed -i "s#https://dl.bintray.com/rackhd/debian trusty main#deb https://roebling.hwimo.lab.emc.com/artifactory/${STAGE_REPO_NAME} ${DEB_DISTRIBUTION} ${DEB_COMPONENT}#" main.yml
cd $WORKSPACE

# Modify the default "apt-get update" ansible role as below
# to ensure the node can access the EMC Artifactory
# "apt" is the first step of the ansible roles
cat > $WORKSPACE/packer/ansible/roles/apt/tasks/main.yml  << EOF
---
- name: Create /usr/local/share/ca-certificates
  shell: mkdir -p /usr/local/share/ca-certificates

- name: Create emcssl.crt
  shell: cat EMCSSL      /usr/local/share/ca-certificates/emcssl.crt

- name: Create emcsslchain.crt
  shell: cat EMCSSLCHAIN /usr/local/share/ca-certificates/emcsslchain.crt

- name: Update CA certificates 
  shell: sudo /usr/sbin/update-ca-certificates -v

- name: Update apt
  apt: update-cache=yes
  sudo: yes
EOF

#Remove EMC CA from the ova/vagrant
# "rackhd-builds" is the last step of the ansible roles
cat >> $WORKSPACE/packer/ansible/roles/rackhd-builds/tasks/main.yml << EOF
- name: Remove EMC CA
  shell: rm -f /usr/local/share/ca-certificates/*    ||     rm -f /etc/ssl/certs/emc*
EOF



cd ..
pkill packer
pkill vmware
set -x
cd $WORKSPACE/build/packer 
export PACKER_CACHE_DIR=$HOME/.packer_cache
export BUILD_TYPE=vmware
#export vars to build ova
if [ "${IS_OFFICIAL_RELEASE}" == true ]; then
    export ANSIBLE_PLAYBOOK=rackhd_release
else
    export ANSIBLE_PLAYBOOK=rackhd_ci_builds
fi
export RACKHD_VERSION=$RACKHD_VERSION
#export end

./HWIMO-BUILD

mv rackhd-${OS_VER}.ova rackhd-${OS_VER}-${RACKHD_VERSION}.ova

