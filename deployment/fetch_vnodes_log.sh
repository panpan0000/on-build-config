#!/bin/bash -x
set +e
vncRecordStart(){
    pushd ${ON_BUILD_CONFIG_DIR}/deployment
    export fname_prefix="vNode"
    if [ ! -z $BUILD_ID ]; then
        export fname_prefix=${fname_prefix}_b${BUILD_ID}
    fi
    bash vnc_record.sh "${BMC_ACCOUNT_LIST}" ${LOG_DIR} $fname_prefix &
    popd
}

vncRecordStop(){
    #sleep 2 sec to ensure FLV finishes the disk I/O before VM destroyed
    pkill -f flvrec.py
    sleep 2
}

fetchSolLogStart(){
    pushd ${ON_BUILD_CONFIG_DIR}/deployment
    bash generate_sol_log.sh "${BMC_ACCOUNT_LIST}" ${LOG_DIR} > ${LOG_DIR}/sol_script.log &
    popd
}

fetchSolLogStop(){
    pkill -f SCREEN
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
            -a | --BMC_ACCOUNT_LIST )       shift
                                            BMC_ACCOUNT_LIST=$1
                                            ;;
            -b | --ON_BUILD_CONFIG_DIR )    shift
                                            ON_BUILD_CONFIG_DIR=$1
                                            ;;
            * )                             Usage
                                            exit 1
        esac
        shift
    done

    if [ ! -n "${LOG_DIR}" ]; then
        echo "[Error]Arguments -l | --LOG_DIR is required"
        Usage
        exit 1
    fi
    if [ ! -n "${BMC_ACCOUNT_LIST}" ]; then
        echo "[Error]Arguments -a | --BMC_ACCOUNT_LIST is required"
        Usage
        exit 1
    fi
    if [ ! -n "${ON_BUILD_CONFIG_DIR}" ]; then
        echo "[Error]Arguments -b | --ON_BUILD_CONFIG_DIR is required"
        Usage
        exit 1
    fi
    mkdir -p ${LOG_DIR}
}


######################################################
#
# Main
#
######################################################
OPERATION=$1
case "$1" in
  start)
      shift
      parseArguments $@
      vncRecordStart
      fetchSolLogStart
  ;;

  stop)
      shift
      vncRecordStop
      fetchSolLogStop
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

