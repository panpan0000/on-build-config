#!/bin/bash -e


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
    # docker -v will show "Docker version 17.03.1-ce, build c6d412e"

    if [ "$docker_version" == "" ]; then
         echo "[Error] Docker is not Installed!"
         result=false
    fi

    local verified_docker_version=17.03.1-ce
    if  $(version_gt  $verified_docker_version $docker_version)  ; then
        echo "[Warning] Installed docker version($docker_version) is lower than verifed docker version $verified_docker_version"
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
    if [ ! $progress -lt 1 ]; then
        deployVNodes.sh           cleanUp
    fi
    if [ ! $progress -lt 2 ]; then
        deployRackHD_from_src.sh  cleanUp
    fi
    if [ ! $progress -lt 3 ]; then
        deployVSwitch.sh          cleanUp
    fi

}



####################################
#
# Main
#
###################################
main(){
    local progress=0

    check_prerequisite

    
    trap "cleanUp $progress " SIGINT SIGTERM SIGKILL EXIT

    SCRIPT=$(readlink -f "$0")
    SCRIPTPATH=$(dirname "$SCRIPT")

    echo $SCRIPTPATH

    ${SCRIPTPATH}/deployVSwitch.sh          deploy
    if [ $? -eq 0 ]; then          progress=1;   else exit $?;   fi

    ${SCRIPTPATH}/deployRackHD_from_src.sh  deploy
    if [ $? -eq 0 ]; then          progress=2;   else exit $?;   fi

    ${SCRIPTPATH}/deployVNodes.sh           deploy
    if [ $? -eq 0 ]; then          progress=3;   else exit $?;   fi

    runFIT.sh
}




main $@
