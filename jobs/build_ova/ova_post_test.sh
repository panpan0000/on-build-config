#!/bin/bash +xe

PACKERDIR="${WORKSPACE}/build/packer/"
OVA="${PACKERDIR}/rackhd-${OS_VER}-${RACKHD_VERSION}.ova"

echo "Post Test starts : OVA File is $OVA"

bash ./build-config/build-release-tools/post_test.sh \
--type ova \
--adminIP ${OVA_Admin_IP} \
--adminGateway ${OVA_Admin_GW} \
--adminNetmask 255.255.255.0 \
--adminDNS ${OVA_Admin_DNS} \
--datastore ${ESXI_DataStore} \
--deployName ova-for-post-test \
--ovaFile $OVA \
--vcenterHost ${VCENTER_IP} \
--ntName ${VCENTER_NT_USER} \
--ntPass ${VCENTER_NT_PASSWORD} \
--esxiHost ${ESXI_HOST_IP} \
--esxiHostUser ${ESXI_USER} \
--esxiHostPass ${ESXI_PASS} \
--net "ADMIN"="Admin" \
--rackhdVersion $RACKHD_VERSION
