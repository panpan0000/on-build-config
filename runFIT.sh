#!/bin/bash -e
#############################################
#
# Global Variable
############################################
RACKHD_DOCKER_NAME=my/test

#############################################
#
# Usage
############################################
Usage(){
    set +x
    echo "Function: This script is used to set up environment for FIT and run FIT."
    echo "Usage: $0 [OPTIONS]"
    echo "  OPTIONS:"
    echo "    Mandatory options:"
    echo "      -w, --WORKSPACE: The directory of workspace( where the code will be cloned to and staging folder), it's required"
    echo "      -p, --SUDO_PASSWORD: password of current user which has sudo privilege, it's required."
    echo "    Optional options:"
    echo "      -b, --ON_BUILD_CONFIG_DIR: The directory of repository on-build-config"
    echo "                       If it's not provided, the script will clone the latest repository on-build-config under $WORKSPACE"
    echo "      -r, --RACKHD_DIR: The directory of repository RackHD"
    echo "                       If it's not provided, the script will clone the latest repository RackHD under $WORKSPACE"
    set -x
}

#############################################
#
#  Start to take the vnc record of nodes 
#
############################################
vnc_record_start(){
    mkdir -p ${WORKSPACE}/build-log
    pushd ${ON_BUILD_CONFIG_DIR}
    export fname_prefix="vNode"
    if [ ! -z $BUILD_ID ]; then
        export fname_prefix=${fname_prefix}_b${BUILD_ID}
    fi
    bash vnc_record.sh ${WORKSPACE}/build-log $fname_prefix &
    popd
}

#############################################
#
#  Stop to take the vnc record of nodes
#
############################################
vnc_record_stop(){
    #sleep 2 sec to ensure FLV finishes the disk I/O before VM destroyed
    set +e
    pkill -f flvrec.py
    sleep 2
    set -e
}

#############################################
#
#  Start to export the sol log of nodes
#
############################################
exportSolLogStart(){
    pushd ${ON_BUILD_CONFIG_DIR}
    bash generate-sol-log.sh > ${WORKSPACE}/sol.log &
    popd
}

#############################################
#
#  Stop to export the sol log of nodes
#
############################################
exportSolLogStop(){
    set +e
    pkill -f SCREEN
}

#############################################
#
#  Start to export the syslog of RackHD container
#
############################################
exportSysLog(){
    set +e
    containerId=$( docker ps|grep "${RACKHD_DOCKER_NAME}" | awk '{print $1}' )
    echo $SUDO_PASSWORD |sudo -S docker exec -it $containerId dmesg > ${WORKSPACE}/build-log/dmesg.log
}

#############################################
#
#  Start to export the mongo of RackHD container
#
############################################
exportMongoLog(){
    set +e
    containerId=$( docker ps|grep "${RACKHD_DOCKER_NAME}" | awk '{print $1}' )
    echo $SUDO_PASSWORD |sudo -S docker cp $containerId:/var/log/mongodb ${WORKSPACE}/build-log
    echo $SUDO_PASSWORD |sudo -S chown -R $USER:$USER ${WORKSPACE}/build-log/mongodb
}

#############################################
#
# Stop to take the vnc record of nodes
# Stop to export the sol log of nodes
# Export the syslog and mongodb from RackHD container 
#
############################################
cleanUp(){
    vnc_record_stop
    exportSolLogStop
    exportSysLog
    exportMongoLog
}

#############################################
#
#  Create the virtual env for FIT  
#
############################################
setupVirtualEnv(){
    pushd ${RACKHD_DIR}/test
    rm -rf .venv/on-build-config
    ./mkenv.sh on-build-config
    source myenv_on-build-config
    popd
}

####################################
#
# 1. Modify FIT config files , to  using actual DHCP Host IP instead of 172.31.128.1
#
##################################
setupTestsConfig(){
    echo "SetupTestsConfig ...replace the 172.31.128.1 IP in test configs with actual DHCP port IP"
    RACKHD_DHCP_HOST_IP=$(ifconfig | awk '/inet addr/{print substr($2,6)}' |grep 172.31.128)
    if [ "$RACKHD_DHCP_HOST_IP" == "" ]; then
         echo "[Error] There should be a NIC with 172.31.128.xxx IP in your OS."
         exit -2
    fi
    pushd ${RACKHD_DIR}/test/config
    sed -i "s/\"username\": \"vagrant\"/\"username\": \"${USER}\"/g" credentials_default.json
    sed -i "s/\"password\": \"vagrant\"/\"password\": \"$SUDO_PASSWORD\"/g" credentials_default.json
    popd
    pushd ${RACKHD_DIR}/test
    find ./ -type f -exec sed -i -e "s/172.31.128.1/${RACKHD_DHCP_HOST_IP}/g" {} \;
    popd
}

####################################
#
# Collect the test report
#
##################################
collectTestReport()
{
    mkdir -p ${WORKSPACE}/xunit-reports
    cp ${RACKHD_DIR}/test/*.xml ${WORKSPACE}/xunit-reports
}


####################################
#
# Start to run FIT tests
#
##################################
runFIT() {
    set +e
    netstat -ntlp
    echo "########### Run FIT Stack Init #############"
    pushd ${RACKHD_DIR}/test
    #TODO Parameterize FIT args
    tstack="-stack docker_local_run"
    args=()
    if [ ! -z "$1" ];then
        args+="$1"
    fi
    python run_tests.py -test deploy/rackhd_stack_init.py ${tstack} ${args} -xunit
    if [ $? -ne 0 ]; then
        echo "Test FIT failed running deploy/rackhd_stack_init.py"
        collectTestReport
        exit 1
    fi
    echo "########### Run FIT Smoke Test #############"
    python run_tests.py ${TEST_GROUP} ${tstack} ${args} -v 4 -xunit
    if [ $? -ne 0 ]; then
        echo "Test FIT failed running smoke test"
        collectTestReport
        exit 1
    fi
    collectTestReport
    popd
    set -e
}


##############################################
#
# Set up test environment and run test
#
#############################################
runTests(){
    OVERALL_STATUS="FAILURE_EXIT"
    trap "cleanUp $OVERALL_STATUS" SIGINT SIGTERM SIGKILL EXIT
    setupTestsConfig
    setupVirtualEnv
    exportSolLogStart
    vnc_record_start
    runFIT " --sm-amqp-use-user guest"
    OVERALL_STATUS="SUCCESSFUL_EXIT"
}

##############################################
#
# Back up exist dir or file
#
#############################################
backupFile(){
    if [ -d $1 ];then
        mv $1 $1-bk
    fi
    if [ -f $1 ];then
        mv $1 $1.bk
    fi
}

#######################################
#
# Main
#
#####################################
main(){
    while [ "$1" != "" ]; do
        case $1 in
            -w | --WORKSPACE )              shift
                                            WORKSPACE=$1
                                            ;;
            -b | --ON_BUILD_CONFIG_DIR )    shift
                                            ON_BUILD_CONFIG_DIR=$1
                                            ;;
            -r | --RACKHD_DIR )             shift
                                            RACKHD_DIR=$1
                                            ;;
            -p | --SUDO_PASSWORD )          shift
                                            SUDO_PASSWORD=$1
                                            ;;
            -g | --TEST_GROUP )             shift
                                            TEST_GROUP=$1
                                            ;;
            * )                             echo "[Error]$0: Unkown Argument: $1"
                                            Usage
                                            exit 1
        esac
        shift
    done
    if [ ! -n "$WORKSPACE" ]; then
        echo "The argument -w|--WORKSPACE is required"
        exit 1
    else
        if [ ! -d "${WORKSPACE}" ]; then
            mkdir -p ${WORKSPACE}
        fi
    fi

    if [ ! -n "$SUDO_PASSWORD" ]; then
        echo "The argument -p|--SUDO_PASSWORD is required"
        exit 1
    fi

    if [ ! -n "$ON_BUILD_CONFIG_DIR" ]; then
        pushd $WORKSPACE
        backupFile on-build-config
        git clone https://github.com/RackHD/on-build-config
        ON_BUILD_CONFIG_DIR=$WORKSPACE/on-build-config
        popd
    fi

    if [ ! -n "$RACKHD_DIR" ]; then
        pushd $WORKSPACE
        backupFile RackHD
        git clone https://github.com/RackHD/RackHD
        RACKHD_DIR=$WORKSPACE/RackHD
        popd

    fi
    if [ ! -n "$TEST_GROUP" ]; then
        TEST_GROUP="-test tests -group smoke"
    fi

    runTests   
}

main "$@"
