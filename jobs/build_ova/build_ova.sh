#!/bin/bash

#sudo cp ${HOME}/bin/packer   /usr/bin
#sudo apt-get install -y  jq

cd $WORKSPACE/build/packer/ansible/roles/rackhd-builds/tasks
ARTIFACTORY_URL=http://afeossand1.cec.lab.emc.com/artifactory

cd $WORKSPACE/build/packer/ansible/roles/rackhd-builds/tasks
sed -i "s#https://dl.bintray.com/rackhd/debian trusty release#${ARTIFACTORY_URL}/${STAGE_REPO_NAME} ${DEB_DISTRIBUTION} ${DEB_COMPONENT}#" main.yml
sed -i "s#https://dl.bintray.com/rackhd/debian trusty main#${ARTIFACTORY_URL}/${STAGE_REPO_NAME} ${DEB_DISTRIBUTION} ${DEB_COMPONENT}#" main.yml
cd $WORKSPACE

echo "kill previous running packer instances"

set +e
cd ..
pkill packer
pkill vmware
set -e
set -x
cd $WORKSPACE/build/packer 
echo "Start to packer build .."

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

