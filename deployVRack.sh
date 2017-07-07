#!/bin/bash -e

#############################################
#
# Usage
#
# ############################################
Usage(){
    echo "*****************************************************************************"
    echo " Function: help to deploy RackHD/InfraSIM as a virtual Rack, then run FIT."
    echo ""
    echo ""
    echo " Prerequisite:"
    echo "      - docker installed."
    echo "      - open vswitch installed."
    echo "      - a NIC with IP 172.31.128.x(typically eth1)"
    echo ""
    echo ""
    echo " Usage: $0 [option] [arguments]"
    echo "  option:"
    echo "    deploy : create a vRack: deploy RackHD and InfraSIM in docker "
    echo "    test   : when if vRack has been deployed. run FIT test"
    echo "    cleanup: remove the docker images and restore network setting"
    echo "    help   : give this help list"
    echo ""
    echo "   Mandatory arguments:"
    echo "      -w, --WORKSPACE: the directory of workspace( where the code will be cloned to and staging folder), it's required"
    echo "      -p, --SUDO_PASSWORD: password of current user which has sudo privilege, it's required."
    echo ""
    echo "    Optional Arguments:"
    echo "        -g, --TEST_GROUP:  the test cases group name to be run in FIT"
    echo "        -c, --VNODE_COUNT: the number of InfraSIM vNode to be deployed"
    echo "*****************************************************************************"
}


#############################################
#
# Global Variable
############################################
SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
DEPLOY_RACKHD_ARGS=()
FIT_ARGS=()

####################################
# helpful fucntion: compare two version string
###################################
version_gt(){
     test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1";
}

####################################
# check prerequisite
###################################
check_prerequisite(){
    local result=true;
    local docker_version=$(docker -v| grep -Po '(Docker version )\d*.\d*.\d*[-ce]*' | awk '{print $NF}')
    local open_vswitch_version=$( ovs-vsctl --version |grep '(Open vSwitch) .*'|awk '{print $NF}' )
    # docker -v will show "Docker version 17.03.1-ce, build c6d412e"

    if [ "$docker_version" == "" ]; then
         echo "[Error] Docker is not Installed!"
         result=false
    fi

    if [ "$open_vswitch_version" == "" ]; then
         echo "[Error] Open VSwitch is not Installed!"
         result=false
    fi

    local verified_docker_version=17.03.1-ce
    if  $(version_gt  $verified_docker_version $docker_version)  ; then
        echo "[Warning] Installed docker version($docker_version) is lower than verifed docker version $verified_docker_version"
    fi

    local verified_open_vswitch_version=2.0.2
    if  $(version_gt  $verified_open_vswitch_version $open_vswitch_version)  ; then
        echo "[Warning] Installed Open VSwitch version($open_vswitch_version) is lower than verifed Open VSwitch version $verified_open_vswitch_version"
    fi

    if [ "$result" == "true" ]; then
         return 0
    else
         return 1
    fi

}

####################################
# Clean Up and Restore
###################################
cleanUp(){
    local progress=$1
    if [ ! $progress -lt 2 ]; then
        ${SCRIPTPATH}/deployVNodes.sh           cleanUp -w $WORKSPACE -p $SUDO_PASSWORD
    fi
    if [ ! $progress -lt 1 ]; then
        ${SCRIPTPATH}/deployRackHD_from_src.sh  cleanUp -w $WORKSPACE -p $SUDO_PASSWORD
    fi
    if [ ! $progress -lt 0 ]; then
        ${SCRIPTPATH}/deployVSwitch.sh          cleanUp -w $WORKSPACE -p $SUDO_PASSWORD
    fi

}



####################################
#
# deploy RackHD and virtual Nodes
#
###################################
deploy(){
    local progress=0

    check_prerequisite
    
    ${SCRIPTPATH}/deployVSwitch.sh          deploy -p $SUDO_PASSWORD
    if [ $? -eq 0 ]; then          progress=1;   else exit $?;   fi

    ${SCRIPTPATH}/deployRackHD_from_src.sh  deploy -p $SUDO_PASSWORD -w $WORKSPACE "$DEPLOY_RACKHD_ARGS"
    if [ $? -eq 0 ]; then          progress=2;   else exit $?;   fi

    ${SCRIPTPATH}/deployVNodes.sh           deploy -p $SUDO_PASSWORD -c ${VNODE_COUNT}
    if [ $? -eq 0 ]; then          progress=3;   else exit $?;   fi
}

####################################
#
# run FIT test
#
###################################
runTests(){
    ${SCRIPTPATH}/runFIT.sh -w $WORKSPACE -p $SUDO_PASSWORD -g $TEST_GROUP "$FIT_ARGS"
}

###################################################################
#
#  Parse and check Arguments
#
##################################################################
parseArguments(){
    while [ "$1" != "" ]; do
        case $1 in
            -w | --WORKSPACE )              shift
                                            WORKSPACE=$1
                                            ;;
            -p | --SUDO_PASSWORD )          shift
                                            SUDO_PASSWORD=$1
                                            ;;
            -g | --TEST_GROUP )             shift
                                            TEST_GROUP=$1
                                            ;;
            -c | --VNODE_COUNT )            shift
                                            VNODE_COUNT=$1
                                            ;;
            * )                             Usage
                                            exit 1
        esac
        shift
    done

    if [ ! -n "${WORKSPACE}" ]; then
        echo "Arguments -w|--WORKSPACE is required!"
        echo "----------------------------------"
        Usage
        exit 1
    fi

    if [ ! -n "${SUDO_PASSWORD}" ]; then
        echo "Arguments -p|--SUDO_PASSWORD is required"
        echo "----------------------------------"
        Usage
        exit 1
    fi

    if [ ! -n "${ON_BUILD_CONFIG_DIR}" ]; then
        if [ -d $WORKSPACE/on-build-config ]; then
            ON_BUILD_CONFIG_DIR=$WORKSPACE/on-build-config
            DEPLOY_RACKHD_ARGS+=" -b $ON_BUILD_CONFIG_DIR"
            FIT_ARGS+=" -b $ON_BUILD_CONFIG_DIR"
        fi
    fi

    if [ ! -n "${RACKHD_DIR}" ]; then
        if [ -d $WORKSPACE/RackHD ]; then
            RACKHD_DIR=$WORKSPACE/RackHD
            FIT_ARGS+=" -r ${RACKHD_DIR}"
        fi
    fi

    if [ ! -n "${RACKHD_IMAGE_PATH}" ]; then
        if [ -f $WORKSPACE/rackhd_pipeline_docker.tar ]; then
            RACKHD_IMAGE_PATH=$WORKSPACE/rackhd_pipeline_docker.tar
            DEPLOY_RACKHD_ARGS+=" -i ${RACKHD_IMAGE_PATH}"
        fi
    fi

    if [ ! -n "${SRC_CODE_DIR}" ]; then
        if [ -d $WORKSPACE/build-deps ]; then
            SRC_CODE_DIR=${WORKSPACE}/build-deps
            DEPLOY_RACKHD_ARGS+=" -s ${SRC_CODE_DIR}"
        fi
    fi

    if  [ ! -n "${VNODE_COUNT}" ];  then
        VNODE_COUNT=2
    fi

    if [ ! -n "$TEST_GROUP" ]; then
        TEST_GROUP="-test tests -group smoke"
    fi
}

case "$1" in
  cleanUp)
      shift
      parseArguments $@
      cleanUp
  ;;

  deploy)
      shift
      parseArguments $@
      deploy
  ;;

  test)
      shift
      parseArguments $@
      runTests
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


