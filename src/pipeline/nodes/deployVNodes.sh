#!/bin/bash -ex
export VCOMPUTE=("${NODE_NAME}-Rinjin1","${NODE_NAME}-Rinjin2","${NODE_NAME}-Quanta")
Usage(){
    echo "to do"
}

nodesOff() {
    pushd ${ON_BUILD_CONFIG_DIR}/deployment/
    for i in ${VCOMPUTE[@]}; do
        ./vm_control.sh "${ESXI_HOST},${ESXI_USER},${ESXI_PASS},power_off,1,${i}_*"
    done
    popd
}

nodesOn() {
    pushd ${ON_BUILD_CONFIG_DIR}/deployment/
    for i in ${VCOMPUTE[@]}; do
        ./vm_control.sh "${ESXI_HOST},${ESXI_USER},${ESXI_PASS},power_on,1,${i}_*"
    done
    popd
}

nodesDelete() {
    pushd ${ON_BUILD_CONFIG_DIR}/deployment/
    for i in ${VCOMPUTE[@]}; do
        ./vm_control.sh "${ESXI_HOST},${ESXI_USER},${ESXI_PASS},delete,1,${i}_*"
    done
    popd
}

nodesCreate() {
    pushd ${ON_BUILD_CONFIG_DIR}/deployment/
    for i in {1..2}; do
      execWithTimeout "ovftool --overwrite --noSSLVerify --diskMode=${DISKMODE} --datastore=${DATASTORE}  --name='${NODE_NAME}-Rinjin${i}' --net:'${NIC}=${NODE_NAME}-switch' '${HOME}/isofarm/OVA/vRinjin-Haswell.ova'   vi://${ESXI_USER}:${ESXI_PASS}@${ESXI_HOST}"
    done
    execWithTimeout "ovftool --overwrite --noSSLVerify --diskMode=${DISKMODE} --datastore=${DATASTORE} --name='${NODE_NAME}-Quanta' --net:'${NIC}=${NODE_NAME}-switch' '${HOME}/isofarm/OVA/vQuanta-T41-Haswell.ova'   vi://${ESXI_USER}:${ESXI_PASS}@${ESXI_HOST}"
    popd
}

vnc_record_start(){
    pushd ${ON_BUILD_CONFIG_DIR}
    export fname_prefix="vNode"
    if [ ! -z $BUILD_ID ]; then
        export fname_prefix=${fname_prefix}_b${BUILD_ID}
    fi
    bash vnc_record.sh ${LOG_DIR} $fname_prefix &
    popd
}

vnc_record_stop(){
    #sleep 2 sec to ensure FLV finishes the disk I/O before VM destroyed
    set +e
    pkill -f flvrec.py
    sleep 2
    set -e
}

generateSolLog(){
    pushd ${ON_BUILD_CONFIG_DIR}
    bash generate-sol-log.sh > ${LOG_DIR}/sol_script.log &
    popd
}

generateSolLogStop(){
    set +e
    pkill -f SCREEN
}


deploy(){
    nodesCreate
    nodesOn
    generateSolLog
    vnc_record_start
}

cleanUp(){
    vnc_record_stop
    generateSolLogStop
    nodesDelete
}

###################################################################
#
#  Parse and check Arguments
#
##################################################################
parseArguments(){
    while [ "$1" != "" ]; do
        case $1 in
            -l | --LOG_DIR )                shift
                                            LOG_DIR=$1
                                            ;;
            -b | --ON_BUILD_CONFIG_DIR )    shift
                                            ON_BUILD_CONFIG_DIR=$1
                                            ;;
            
            * )                             Usage
                                            exit 1
        esac
        shift
    done
    mkdir -p ${LOG_DIR}

}

########################################################
#
# Main
#
######################################################
OPERATION=$1
case "$1" in
  cleanUp|cleanup)
      shift
      parseArguments $@
      cleanUp
  ;;

  deploy)
      shift
      parseArguments $@
      deploy
  ;;

  -h|--help|help)
    Usage
    exit 0
  ;;

  *)
    Usage
    exit 1
  ;;

esac

