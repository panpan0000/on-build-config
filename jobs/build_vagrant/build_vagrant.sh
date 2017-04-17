#!/bin/bash
set +e
ifconfig

packer -v  # $? of "packer -v" is 1 ...
vagrant -v
set -e

ARTIFACTORY_URL=http://afeossand1.cec.lab.emc.com/artifactory
echo "Modify rackhd-builds ansible role to redirect to Artifactory.."

cd $WORKSPACE/build/packer/ansible/roles/rackhd-builds/tasks
sed -i "s#https://dl.bintray.com/rackhd/debian trusty release#${ARTIFACTORY_URL}/${STAGE_REPO_NAME} ${DEB_DISTRIBUTION} ${DEB_COMPONENT}#" main.yml
sed -i "s#https://dl.bintray.com/rackhd/debian trusty main#${ARTIFACTORY_URL}/${STAGE_REPO_NAME} ${DEB_DISTRIBUTION} ${DEB_COMPONENT}#" main.yml
cd $WORKSPACE


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
