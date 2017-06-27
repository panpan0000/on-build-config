#!/bin/bash -ex

Usage()
{
    echo "Function: this script is used to power_on/power_off/delete VMs"
    echo "Usage: OPTION SERVER_INFO [SERVER_INFO]"
    echo "  OPTION:"
    echo "    -h: give this help list"
    echo "    -f: Obtain SERVER_INFO from FILE, one per line.  The empty file contains zero INFO, and therefore matches nothing."
    #echo "    -a: the aciton should be taken on the specific VM. \"power_on\",\"power_off\" and \"delete\" are supported"
    echo "  SERVER_INFO: \"ip,user_name,password,action,duration,vm_name[,vm_name]\" "
    echo "    ip       : the IP address of ESXi server"
    echo "    user_name: the user name of ESXi server"
    echo "    password : the password of ESXi server."
    echo "    action   : the action should be taken on the specific VM. power_on,power_off and delete are supported"
    echo "    duration :the duration time between the action, the unit is second(s)"
    echo "    vm_name  : the name of VM which will be operated. Regular Expression is supported"
}


#NODE_TYPE=()
API_PACKAGE_LIST="on-http-api2.0 on-http-redfish-1.0"
##############################################################
## Pre-condition:
# (1)RackHD all repos code are cloned and npm-installed in folder : ${WORKSPACE}/${SRC_CODE}
# (2) RackHD repo only as tests repo in folder  ${WORKSPACE}/RackHD
# (3) on-build-config repo is cloned in ${WORKSPACE}/${ON_BUILD_CONFIG}
# (4) rackhd_pipeline_docker.tar downloaded from Jenkins archieve and places in  $WORKSPACE
# (5) Docker CE installed
#
# Parameters(ENV Variables):
# NODE_NAME  - Jenkins build-in Env Var. the running slave name
# USER       - Jenkins build-in Env Var. the account runs this script on vmslave
# WORKSPACE  - Jenkins build-in Env Var. the working folder
# BUILD_ID   - Jenkins build-in Env Var. the Jenkins Build ID digit.
# SRC_CODE   - the folder name inside ${WORKSPACE}, which all RackHD source code live
# ON_BUILD_CONFIG -  the folder name inside ${WORKSPACE}, which on-build-config repo live
# VNODE_COUNT  - How Many vNodes will be deployed
# MODIFY_API_PACKAGE -  true if RackHD/on-http repo under test
# API_PACKAGE_LIST   -  "on-http-api2.0 on-http-redfish-1.0"
# SUDO_PASSWORD - the password of default account in running OS (vmslave)
# TEST_GROUP - varies for FIT or CIT. example: "-test tests -group smoke" for FIT Smoke.
# TEST_TYPE  - How RackHD under test lives: manifest/ova/docker.
# TEST_STACK - the FIT Test Stack mapping to config files: example "-stack docker_local_run" , "-stack vagrant"...
# EXTRA_HW   - Physical Stack : Hardware Array
# BASE_REPO_URL - the base repo URL for OS Installation image repo. default http://172.31.128.1:8080
# TEST_UCS   - if UCS is included in this test. default true
##############################################################



#############################################
#
# Global Variable
############################################
RACKHD_DOCKER_NAME="my/test"
OV_BRIDGE=ovs-br0   # Open VSwitch Bridge Name in Host
INFRASIM_DOCKER=infrasim/infrasim-compute
INFRASIM_DOCKER_TAG=latest #infrasim-compute_227b
NODE_TYPE_ARRAY=(dell_r630 s2600kp dell_c6320 dell_r730 quanta_d51 quanta_t41 s2600tp)
INFRSIM_RAM=2048

##############################################
#
#Clean Up docker images with name ${RACKHD_DOCKER_NAME}
#
##########################################
cleanUpDockerImages(){
    set +e
    local to_be_removed="$(docker images ${RACKHD_DOCKER_NAME} -q)  \
                         $(docker images rackhd/pipeline -q)  \
                         $(docker images -f "dangling=true" -q )"
    # remove ${RACKHD_DOCKER_NAME} image,  rackhd/pipeline image and <none>:<none> images
    if [ "$to_be_removed" != "" ]; then
         echo $SUDO_PASSWORD |sudo -S docker rmi $to_be_removed
    fi
    set -e
}
##############################################
#
# Remove docker instance which are running
#
###########################################
cleanUpDockerContainer(){
    set +e
    local running_docker=$(docker ps -a -q)
    if [ "$running_docker" != "" ]; then
         docker stop $running_docker
         docker rm   $running_docker
    fi
    set -e
}

######################################
#
# Clean Up runnning docker instance
#
#####################################
cleanup_dockers(){
    echo "CleanUp Dockers ..."
    set +e
    cleanUpDockerContainer
    cleanUpDockerImages
    set -e
}
#########################################
#
# Start Host services to avoid noise
#
#######################################
start_services(){
    echo "Stop Services (mongo/rabbitmq)..."
    set +e
    echo $SUDO_PASSWORD |sudo -S service mongodb start
    echo $SUDO_PASSWORD |sudo -S service rabbitmq-server start
    set -e
}

#########################################
#
# Stop Host services to avoid noise
#
#######################################
stop_services(){
    echo "Stop Services (mongo/rabbitmq)..."
    set +e
    echo $SUDO_PASSWORD |sudo -S service mongodb stop
    echo $SUDO_PASSWORD |sudo -S service rabbitmq-server stop
    set -e
}

#######################################
#
# Set up Network in Host( Open vSwitch Bridge)
#
#####################################

setup_host_network(){
   local RACKHD_DHCP_HOST_IP=$(ifconfig | awk '/inet addr/{print substr($2,6)}' |grep 172.31.128)
   if [ "$RACKHD_DHCP_HOST_IP" == "" ]; then
         echo "[Error] There should be a NIC with 172.31.128.xxx IP in your OS."
         exit -2
   fi
   local RACKHD_DHCP_NIC=$( ifconfig | awk '/172.31.128/ {print $1}' RS="\n\n" )
   echo "Debug: RackHD DHCP NIC is $RACKHD_DHCP_NIC, IP was $RACKHD_DHCP_HOST_IP."
   echo $SUDO_PASSWORD |sudo -S ovs-vsctl add-br ${OV_BRIDGE}
   echo $SUDO_PASSWORD |sudo -S ovs-vsctl add-port ${OV_BRIDGE} $RACKHD_DHCP_NIC
   echo $SUDO_PASSWORD |sudo -S ovs-vsctl set Bridge ${OV_BRIDGE} other_config:stp-forward-delay=0
   echo $SUDO_PASSWORD |sudo -S ovs-vsctl set Bridge ${OV_BRIDGE} other_config:stp-hello-time=1
   echo $SUDO_PASSWORD |sudo -S ovs-vsctl set Bridge ${OV_BRIDGE} stp_enable=no
   echo $SUDO_PASSWORD |sudo -S ip link set dev ${OV_BRIDGE} up
   echo $SUDO_PASSWORD |sudo -S ifconfig $RACKHD_DHCP_NIC 0
   echo $SUDO_PASSWORD |sudo -S ifconfig $RACKHD_DHCP_NIC promisc
   echo $SUDO_PASSWORD |sudo -S ifconfig  ${OV_BRIDGE} $RACKHD_DHCP_HOST_IP
}
#######################################
#
# Delete bridge and restore em1 IP
#
#####################################
restore_host_network(){
    echo "Restore NIC configurations and delete old open vswitch bridge..."
    set +e
    # delete the bridge created by open vswitch
    local bridges=$(  echo $SUDO_PASSWORD |sudo -S  ovs-vsctl list-br| grep ovs-br )
    if [ "$bridges" != "" ];  then
         local DHCP_NIC=$( echo $SUDO_PASSWORD |sudo -S  ovs-vsctl list-ports ${bridges} | head -n1 )
         local original_ip=$(ifconfig ${bridges} | awk '/inet addr/{print substr($2,6)}')
         echo $SUDO_PASSWORD |sudo -S ovs-vsctl del-br $bridges
         echo $SUDO_PASSWORD |sudo -S ifconfig $DHCP_NIC $original_ip
         echo $SUDO_PASSWORD |sudo -S ifconfig $DHCP_NIC -promisc
    fi
    set -e
}
##############################################
# Clean up previous dirty space before everyting starts
#
#############################################
prepare_env(){
    echo "Prepare Env -----------------Start -------------------"
    cleanup_dockers
    stop_services
    setup_host_network
    echo "Prepare Env -----------------End ---------------------"
}
############################################
#
# Clean Up after script done
#
###########################################
cleanUp(){
    echo "CleanUp [$@]-----------------Start -------------------"
    exportLog    
    cleanup_dockers
    start_services
    restore_host_network
    echo "CleanUp [$@]-----------------End ---------------------"
}


apiPackageModify() {
    pushd ${SRC_CODE_DIR}/on-http/extra
    sed -i "s/.*git symbolic-ref.*/ continue/g" make-deb.sh
    sed -i "/build-package.bash/d" make-deb.sh
    sed -i "/GITCOMMITDATE/d" make-deb.sh
    sed -i "/mkdir/d" make-deb.sh
    bash make-deb.sh
    popd
    for package in ${API_PACKAGE_LIST}; do
      sudo pip uninstall -y ${package//./-} || true
      pushd ${SRC_CODE_DIR}/on-http/$package
        fail=true
        while $fail; do
          python setup.py install
          if [ $? -eq 0 ];then
              fail=false
          fi
        done
      popd
    done
}




ucsReset() {
  cd ${BUILD_CONFIG_DIR}/deployment/
  if [ "${USE_VCOMPUTE}" != "false" ]; then
    for i in ${UCSPE[@]}; do
      ./vm_control.sh "${ESXI_HOST},${ESXI_USER},${ESXI_PASS},reset,1,${i}_*"
    done
  fi
}

prepare_pipework(){
    pushd ${WORKSPACE}
    git config --global http.sslverify false
    if [ "$(which pipework)" == "" ]; then
        git clone https://github.com/jpetazzo/pipework.git
        echo $SUDO_PASSWORD |sudo -S  scp $PWD/pipework/pipework /usr/local/bin/pipework
        echo $SUDO_PASSWORD |sudo -S chmod +x /usr/local/bin/pipework
        popd
    else
        echo "pipework is existing...."
    fi
}


modifyInfrasimConfig(){

     local vnode_id=$1
     local vnode_docker_name=$2
     local config_file=/root/.infrasim/.node_map/default.yml  #config file inside InfraSIM Docker

     docker exec $vnode_docker_name  sed -i "s/type: dell_r730/type: ${NODE_TYPE_ARRAY[$((${vnode_id}-1))]}/"  $config_file
     docker exec $vnode_docker_name  sed -i "s/network_mode: nat/network_mode: bridge/"  $config_file
     docker exec $vnode_docker_name  sed -i "s/network_name: eth0/network_name: br0/"  $config_file
     docker exec $vnode_docker_name  sed -i "s/mac:.*//"  $config_file
     docker exec $vnode_docker_name  sed -i 's/size: 1024/size: ${INFRSIM_RAM}/g' $config_file


}

####################################
#
# Start InfraSIM Docker, then create bridge inside it , bind with ovs-br0 using pipework.
# then Start InfraSIM app.
#
####################################

nodesCreate() {
    prepare_pipework

    local port_num=15901
    local vnode_id
    for vnode_id in $(seq 1 ${VNODE_COUNT})  ; do
        local infrasim_docker_name=idic${vnode_id}
        echo "DEBUG: Create Docker instance : $infrasim_docker_name on Port $port_num "i

        #sudo ./docker.sh -n $infrasim_docker_name -p $port_num
        echo "Start InfraSIM docker"
        docker run --privileged -p $port_num:5901 -dit --name $infrasim_docker_name  ${INFRASIM_DOCKER}:${INFRASIM_DOCKER_TAG} /bin/bash

        # Modify the InfraSIM config file
        modifyInfrasimConfig ${vnode_id} ${infrasim_docker_name}

        echo "Set up pipework bridge"
        echo $SUDO_PASSWORD |sudo -S  /bin/bash $(which pipework) ${OV_BRIDGE} -i eth1 $infrasim_docker_name dhclient

        echo "Set up docker internal bridge"
        docker exec $infrasim_docker_name brctl addbr br0
        docker exec $infrasim_docker_name brctl addif br0 eth1
        docker exec $infrasim_docker_name brctl setfd    br0 0
        docker exec $infrasim_docker_name brctl sethello br0 1
        docker exec $infrasim_docker_name brctl stp      br0 no


        sleep 2
        local retry_counter=0
        local retry_total=10
        local dhcp_ip=""
        while [ ${retry_counter} != ${retry_total} ]; do
              dhcp_ip=$(docker exec $infrasim_docker_name ifconfig eth1 | awk '/inet addr/{print substr($2,6)}')
              if [ "$dhcp_ip" == "" ]; then
                echo "retry to get docker image $infrasim_docker_name IP. maybe it is still under DHCP."
                   sleep 2;
              else
                   break;
              fi
              retry_counter=$(( retry_counter + 1 ))
    done

    if [ "$dhcp_ip" == "" ]; then
       echo "No DHCP services, please check DHCP server."
           exit -1
    else
       echo "docker internal eth1 IP: $dhcp_ip"
        fi
        docker exec $infrasim_docker_name ifconfig eth1 0
        docker exec $infrasim_docker_name ifconfig eth1 promisc
        docker exec $infrasim_docker_name ifconfig br0 $dhcp_ip
        echo "Start InfraSIM node .. "
        docker exec $infrasim_docker_name infrasim node start
        
        port_num=$(( $port_num + 1 ))
    done
}

vnc_record_start(){
  mkdir -p ${WORKSPACE}/build-log
  pushd ${BUILD_CONFIG_DIR}
  export fname_prefix="vNode"
  if [ ! -z $BUILD_ID ]; then
      export fname_prefix=${fname_prefix}_b${BUILD_ID}
  fi
  bash vnc_record.sh ${WORKSPACE}/build-log $fname_prefix &
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
  pushd ${BUILD_CONFIG_DIR}
  bash generate-sol-log.sh > ${WORKSPACE}/sol.log &
  popd
}

generateSolLogStop(){
  set +e
  pkill -f SCREEN
}

generateSysLog(){
  set +e
  containerId=$(  docker ps|grep "${RACKHD_DOCKER_NAME}" | awk '{print $1}' )
  docker exec -it $containerId dmesg > ${WORKSPACE}/build-log/dmesg.log
}

generateMongoLog(){
  set +e
  containerId=$(  docker ps|grep "${RACKHD_DOCKER_NAME}" | awk '{print $1}' )
  echo $SUDO_PASSWORD |sudo -S docker cp $containerId:/var/log/mongodb ${WORKSPACE}/build-log
  echo $SUDO_PASSWORD |sudo -S chown -R $USER:$USER ${WORKSPACE}/build-log/mongodb
}

generateRackHDLog(){
  set +e
  containerId=$( docker ps|grep "${RACKHD_DOCKER_NAME}" | awk '{print $1}' )
  echo $SUDO_PASSWORD |sudo -S docker cp $containerId:/root/.pm2/logs ${WORKSPACE}/build-log
  echo $SUDO_PASSWORD |sudo -S chown -R $USER:$USER ${WORKSPACE}/build-log/logs
  mv ${WORKSPACE}/build-log/logs/*.log ${WORKSPACE}/build-log
}

setupVirtualEnv(){
  pushd ${RACKHD_DIR}/test
  rm -rf .venv/on-build-config
  ./mkenv.sh on-build-config
  source myenv_on-build-config
  popd
  if [ "$MODIFY_API_PACKAGE" == true ] ; then
      apiPackageModify
  fi
}

runTests() {
  set +e
  netstat -ntlp
  args=()
  if [ ! -z "$1" ];then
      args+="$1"
  fi
  fitSmokeTest "${args}"
  set -e
}

waitForAPI() {
  timeout=0
  maxto=60
  set +e
  url=http://localhost:9090/api/2.0/nodes
  while [ ${timeout} != ${maxto} ]; do
    wget --retry-connrefused --waitretry=1 --read-timeout=20 --timeout=15 -t 1 --continue ${url}
    if [ $? = 0 ]; then 
      break
    fi
    sleep 10
    timeout=`expr ${timeout} + 1`
  done
  set -e
  if [ ${timeout} == ${maxto} ]; then
    echo "Timed out waiting for RackHD API service (duration=`expr $maxto \* 10`s)."
    exit 1
  fi
}



dockerUp(){
    pushd $WORKSPACE
    if [ -f rackhd_pipeline_docker.tar ]; then
        echo $SUDO_PASSWORD |sudo -S docker load -i rackhd_pipeline_docker.tar
    fi
    popd
    pushd ${BUILD_CONFIG_DIR}/jobs/pr_gate/docker
    rm -rf build-deps
    mkdir -p build-deps
    cp -r ${SRC_CODE_DIR}/* build-deps
    echo $SUDO_PASSWORD |sudo -S docker build -t ${RACKHD_DOCKER_NAME} .
    echo $SUDO_PASSWORD |sudo -S docker run --net=host -v /etc/localtime:/etc/localtime:ro -d -t ${RACKHD_DOCKER_NAME}
    popd
}

####################################
#
# 1. Modify FIT config files , to  using actual DHCP Host IP instead of 172.31.128.1
# 2. Customize the config.json
#
##################################
setupTestsConfig(){
    echo "SetupTestsConfig ...replace the 172.31.128.1 IP in test configs with actual DHCP port IP"
    RACKHD_DHCP_HOST_IP=$(ifconfig | awk '/inet addr/{print substr($2,6)}' |grep 172.31.128)
    if [ "$RACKHD_DHCP_HOST_IP" == "" ]; then
         echo "[Error] There should be a NIC with 172.31.128.xxx IP in your OS."
         exit -2
    fi
    # modify the config.json, which will be included into RackHD docker images during docker build
    # Ensure this runs before docker-build
    sed -i "s/172.31.128.1/${RACKHD_DHCP_HOST_IP}/g" ${BUILD_CONFIG_DIR}/jobs/pr_gate/docker/monorail/config.json

    pushd ${RACKHD_DIR}/test/config
    sed -i "s/\"username\": \"vagrant\"/\"username\": \"${USER}\"/g" credentials_default.json
    sed -i "s/\"password\": \"vagrant\"/\"password\": \"$SUDO_PASSWORD\"/g" credentials_default.json
    popd
    pushd ${RACKHD_DIR}
    find ./ -type f -exec sed -i -e "s/172.31.128.1/${RACKHD_DHCP_HOST_IP}/g" {} \;
    popd
}

collectTestReport()
{
    mkdir -p ${WORKSPACE}/xunit-reports
    cp ${RACKHD_DIR}/test/*.xml ${WORKSPACE}/xunit-reports
}

fitSmokeTest()
{
    set +e
    echo "########### Run FIT Stack Init #############"
    pushd ${RACKHD_DIR}/test
    #TODO Parameterize FIT args
    tstack="${TEST_STACK}"
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

exportLog(){
    echo "exportLog: Starts"
    set +e
    vnc_record_stop
    generateSolLogStop
    generateRackHDLog
    generateMongoLog
    echo $SUDO_PASSWORD| sudo -S chown -R $USER:$USER ${WORKSPACE}/build-log
    set -e
    echo "exportLog: Ends"
}

###################################################################
#
#  Main
#
##################################################################
main(){

    while [ "$1" != "" ]; do
        case $1 in
            -w | --WORKSPACE )              shift
                                            WORKSPACE=$1
                                            ;;
            -s | --SRC_CODE_DIR )           shift
                                            SRC_CODE_DIR=$1
                                            ;;         
            -b | --BUILD_CONFIG_DIR )       shift
                                            BUILD_CONFIG_DIR=$1
                                            ;;
            -r | --RACKHD_DIR )             shift
                                            RACKHD_DIR=$1
                                            ;;
            -v | --VNODE_COUNT )            shift
                                            VNODE_COUNT=$1
                                            ;;
            -m | --MODIFY_API_PACKAGE )     shift
                                            MODIFY_API_PACKAGE=$1
                                            ;;
            -p | --SUDO_PASSWORD )          shift
                                            SUDO_PASSWORD=$1
                                            ;;
            -u | --UCSPE )                  shift
                                            UCSPE=("$1")
                                            ;;
            -g | --TEST_GROUP )             shift
                                            TEST_GROUP=$1
                                            ;;
            -h | --help )                   Usage
                                            exit
                                            ;;
            * )                             Usage
                                            exit 1
        esac
        shift
    done

    #############################################
    #
    # Default Parameter Checking
    #
    ##########################################
    if  [ ! -n "${VNODE_COUNT}" ];  then
        VNODE_COUNT=2
    fi

    if [ ! -n "${MODIFY_API_PACKAGE}" ]; then
        MODIFY_API_PACKAGE=true
    fi

    if [ ! -n "${TEST_TYPE}" ]; then
        TEST_TYPE="manifest"
    fi

    if  [ ! -n "${TEST_GROUP}" ]; then
        TEST_GROUP="-test tests -group smoke"
    fi

    if  [ ! -n "${TEST_STACK}" ]; then
        TEST_STACK="-stack docker_local_run"
    fi

    if  [ ! -n "${BASE_REPO_URL}" ]; then
        BASE_REPO_URL="http://172.31.128.1:8080"
    fi


    ucsReset
    prepare_env
    OVERALL_STATUS="FAILURE_EXIT"
    # register the signal handler to export log
    trap "cleanUp $OVERALL_STATUS" SIGINT SIGTERM SIGKILL EXIT
    setupTestsConfig
    dockerUp
    waitForAPI # run before InfraSIM docker  up
    nodesCreate # it should run after RackHD up. otherwise, the DHCP inside docker eth1 will hang up
    # Setup the virtual-environment
    setupVirtualEnv

    generateSolLog
    vnc_record_start
    # Run tests
    runTests " --sm-amqp-use-user guest"
    OVERALL_STATUS="SUCCESSFUL_EXIT"
}


################################################
main $@

