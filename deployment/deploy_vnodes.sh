#!/bin/bash -ex
Usage(){
    echo "to do"
}

nodesOff() {
    pushd ${ON_BUILD_CONFIG_DIR}/deployment/
    ./vm_control.sh "${ESXI_HOST},${ESXI_USER},${ESXI_PASS},power_off,1,${VNODE_NAME}"
    popd
}

nodesOn() {
    pushd ${ON_BUILD_CONFIG_DIR}/deployment/
    ./vm_control.sh "${ESXI_HOST},${ESXI_USER},${ESXI_PASS},power_on,1,${VNODE_NAME}"
    popd
}

nodesDelete() {
    pushd ${ON_BUILD_CONFIG_DIR}/deployment/
    ./vm_control.sh "${ESXI_HOST},${ESXI_USER},${ESXI_PASS},delete,1,${VNODE_NAME}"
    popd
}

nodesCreate() {
    pushd ${ON_BUILD_CONFIG_DIR}/deployment/
    execWithTimeout "${ON_BUILD_CONFIG_DIR}" "ovftool --noSSLVerify --diskMode=${DISKMODE} --datastore=${DATASTORE}  --name='${VNODE_NAME}' --net:'${NIC_NAME}=${SWITCH_NAME}' '${OVA_PATH}' vi://${ESXI_USER}:${ESXI_PASS}@${ESXI_HOST}"
    popd
}

deploy(){
    nodesCreate
    nodesOn
}

cleanUp(){
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
            -h | --ESXI_HOST )              shift
                                            ESXI_HOST=$1
                                            ;;
            -u | --ESXI_USER )              shift
                                            ESXI_USER=$1
                                            ;;
            -p | --ESXI_PASS )              shift
                                            ESXI_PASS=$1
                                            ;;
            -n | --NIC_NAME )               shift
                                            NIC_NAME="$1"
                                            ;;
            -s | --SWITCH_NAME )            shift
                                            SWITCH_NAME=$1
                                            ;;
            -d | --DATASTORE )              shift
                                            DATASTORE=$1
                                            ;;
            -m | --DISKMODE )               shift
                                            DISKMODE=$1
                                            ;;
            -v | --VNODE_NAME )             shift
                                            VNODE_NAME=$1
                                            ;;
            -o | --OVA_PATH )               shift
                                            OVA_PATH=$1
                                            ;;
            -b | --ON_BUILD_CONFIG_DIR )    shift
                                            ON_BUILD_CONFIG_DIR=$1
                                            ;;
            * )                             Usage
                                            exit 1
        esac
        shift
    done

    if [ ! -n "${ESXI_HOST}" ]; then
        echo "[Error]Arguments -h | --ESXI_HOST is required"
        Usage
        exit 1
    fi

    if [ ! -n "${ESXI_USER}" ]; then
        echo "[Error]Arguments -u | --ESXI_USER is required"
        Usage
        exit 1
    fi

    if [ ! -n "${ESXI_PASS}" ]; then
        echo "[Error]Arguments -p | --ESXI_PASS is required"
        Usage
        exit 1
    fi

    if [ ! -n "${VNODE_NAME}" ]; then
        echo "[Error]Arguments -n | --VNODE_NAME is required"
        Usage
        exit 1
    fi
    if [${OPERATION,,} == "deploy"]; then
        if [ ! -n "${NIC_NAME}" ]; then
            echo "[Error]Arguments -n | --NIC_NAME is required"
            Usage
            exit 1
        fi
    
        if [ ! -n "${SWITCH_NAME}" ]; then
            echo "[Error]Arguments -s | --SWITCH_NAME is required"
            Usage
            exit 1
        fi
    
        if [ ! -n "${DATASTORE}" ]; then
            echo "[Error]Arguments -d | --DATASTORE is required"
            Usage
            exit 1
        fi
    
        if [ ! -n "${OVA_PATH}" ]; then
            echo "[Error]Arguments -o | --OVA_PATH is required"
            Usage
            exit 1
        fi
    fi

    if [ ! -n "${ON_BUILD_CONFIG_DIR}" ]; then
        echo "[Error]Arguments -b | --ON_BUILD_CONFIG_DIR is required"
        Usage
        exit 1
    fi
    echo "${ON_BUILD_CONFIG_DIR}"
    source ${ON_BUILD_CONFIG_DIR}/shareMethod.sh
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
      parseArguments "$@"
      cleanUp
  ;;

  deploy)
      shift
      parseArguments "$@"
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

