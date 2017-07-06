#!/bin/bash -e

#####################################
#
#  Usage
#
####################################

Usage()
{
    echo "Function: this script is used to deploy/cleanup InfraSIM dockers and setup pipework network "
    echo "Usage: [OPERATION]|--help [OPTION]"
    echo "  OPERATION:"
    echo "    deploy : to deploy InfraSIM in dockers"
    echo "    cleanup: to destroy the running InfraSIM dockers"
    echo "  OPTION:"
    echo "    -c, --VNODE_COUNT  : vNode count: how many infraSIM instance to be created(only required for deploy opertion, default value is 2)"
    echo "    -p, --SUDO_PASSWORD : sudo password of current user with root privileged"
}




#############################################
#
# Global Variable
############################################
OV_BRIDGE=ovs-br0   # Open VSwitch Bridge Name in Host
INFRASIM_DOCKER=infrasim/infrasim-compute
INFRASIM_DOCKER_TAG=infrasim-compute_227db #lock down the version
NODE_TYPE_ARRAY=(quanta_d51 quanta_t41 dell_r630 s2600kp dell_c6320 dell_r730 s2600tp)
INFRSIM_RAM=2048
INFRSIM_INSTANCE_NAME_PREFIX=idic


##############################################
#
# Remove docker instance which are running
#
###########################################
cleanUpDockerContainer(){
    set +e
    CONTAINERS=$(docker ps -a -q --filter ancestor=$INFRASIM_DOCKER --format="{{.ID}}")
    if [ "$CONTAINERS" != "" ]; then
        echo "Stop docker containers..."
        docker stop $CONTAINERS
        echo "Remove docker containers..."
        docker rm $CONTAINERS
    else
        echo "No running infrasim/infrasim-compute containers. skip cleanup"
    fi
    set -e
}


##############################################
#
# Modify InfraSIM config file
#
###########################################
prepare_pipework(){
    if [ "$(which pipework)" == "" ]; then
        pushd /tmp
        rm pipework -rf
        git config --global http.sslverify false
        git clone https://github.com/jpetazzo/pipework.git
        echo $SUDO_PASSWORD |sudo -S  scp $PWD/pipework/pipework /usr/local/bin/pipework
        echo $SUDO_PASSWORD |sudo -S chmod +x /usr/local/bin/pipework
        popd
    else
        echo "pipework is existing....skip prepare_pipework()"
    fi
}


##############################################
#
# Modify InfraSIM config file
#
###########################################
modifyInfrasimConfigFile(){
     local vnode_id=$1
     local vnode_docker_name=$2
     local config_file=/root/.infrasim/.node_map/default.yml  #config file inside InfraSIM Docker

     docker exec $vnode_docker_name  sed -i "s/type: dell_r730/type: ${NODE_TYPE_ARRAY[$((${vnode_id}-1))]}/"  $config_file
     docker exec $vnode_docker_name  sed -i "s/network_mode: nat/network_mode: bridge/"  $config_file
     docker exec $vnode_docker_name  sed -i "s/network_name: eth0/network_name: br0/"  $config_file
     docker exec $vnode_docker_name  sed -i "s/mac:.*//"  $config_file
     docker exec $vnode_docker_name  sed -i 's/size: 1024/size: ${INFRSIM_RAM}/g' $config_file
}


##############################################
#
# Helper Function: retrieve IP from a running Docker image
#
# $1: docker instance name
# $2: the NIC name inside docker instance
# $3: the name of ret value
###########################################
retrieveIPinsideDocker(){
    local docker_name=$1    # e.x: idid1
    local nic_interface=$2  # e.x: eth1

    local ret_var=$3      # will use eval to set its value

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
        return 1
    else
        eval $ret_var="'$dhcp_ip'"   # return the parameter $3 to invoker
        return 0
    fi
   
}

##############################################
#
# Set up Pipework
#
###########################################
setupInfrasimNetwork(){

    local vnode_docker_name=$1

    echo "[Info] Use pipework to create eth1 inside $vnode_docker_name , and try DHCP to retrieve its IP"
    echo $SUDO_PASSWORD |sudo -S  /bin/bash $(which pipework) ${OV_BRIDGE} -i eth1 $infrasim_docker_name dhclient

    echo "[Info] Create br0 inside docker instance $vnode_docker_name"
    # Create br0 inside infrasim docker
    docker exec $infrasim_docker_name brctl addbr    br0
    docker exec $infrasim_docker_name brctl addif    br0 eth1
    docker exec $infrasim_docker_name brctl setfd    br0 0
    docker exec $infrasim_docker_name brctl sethello br0 1
    docker exec $infrasim_docker_name brctl stp      br0 no
    sleep 2

    # retry to obtain eth1's IP inside infrasim instance
    local dhcp_ip=""
    retrieveIPinsideDocker $infrasim_docker_name  "eth1"  "dhcp_ip"  # the 3rd parameter is the ret variable's name
    if [ $? -ne 0 ]; then
        echo "[Error] Timeout waiting for DHCP of Infrasim internal eth1 IP from $vnode_docker_name."
        exit -1
    fi
    echo "[Info] Exchange the eth1 IP with br0 inside $vnode_docker_name"
    docker exec $infrasim_docker_name ifconfig eth1 0
    docker exec $infrasim_docker_name ifconfig eth1 promisc
    docker exec $infrasim_docker_name ifconfig br0 $dhcp_ip

}

##############################################
#
# Pull Docker Image with retry (dockerhub pull are slow in APJ and may end up "docker: unauthorized: authentication required.")
#
###########################################
dockerPullWithRetry(){
    local retry_counter=0
    local docker_image=$1
    local retry_total=$2
    if [ "$docker_image" == "" ]; then
       echo "[Error] in dockerPullWithRetry(), missing argument docker_image"
       exit -1
    fi
    if [ -z $retry_total ]; then
       retry_total=3
    fi
    while [ ${retry_counter} != ${retry_total} ]; do
            docker pull ${docker_image}
            if [ $? -ne 0 ]; then
            echo "retry to pull docker image $docker_image "
        else
            break;
        fi
        retry_counter=$(( retry_counter + 1 ))
    done
}


####################################
#
# start infrasim docker, then create bridge inside it , bind with ovs-br0 using pipework.
# then start infrasim app.
#
####################################
startInfrasimNodes() {

    prepare_pipework

    local port_num=15901 # the Host VNC port base

    local vnode_id
    for vnode_id in $(seq 1 ${vnode_count})  ; do

        local infrasim_docker_name=idic${vnode_id}

        echo "[Info]: create docker instance : $infrasim_docker_name on port $port_num "

        dockerPullWithRetry ${INFRASIM_DOCKER}:${INFRASIM_DOCKER_TAG}   3
        docker run --privileged -p ${port_num}:5901 -dit --name $infrasim_docker_name  ${INFRASIM_DOCKER}:${INFRASIM_DOCKER_TAG} /bin/bash


        # modify the infrasim config file
        modifyInfrasimConfig ${vnode_id} ${infrasim_docker_name}

        # setup Pipework network and InfraSIM br0
        setupInfrasimNetwork ${infrasim_docker_name}

        # start InfraSIM
        echo "[Info] Start InfraSIM node $vnode_docker_name"
        docker exec $infrasim_docker_name infrasim node start
       
        port_num=$(( $port_num + 1 ))

    done
}
################################
#
# Parse the options after deploy|clenup 
#
##############################

parseOptions(){
    while [ "$1" != "" ]; do
        case $1 in
             -c | --VNODE_COUNT )   shift
                                    VNODE_COUNT=$1
                                    ;;
             -p | --SUDO_PASSWORD ) shift
                                    SUDO_PASSWORD=$1
                                    ;;
             * )                    Usage
                                    exit 1
        esac
        shift
    done
    if  [ ! -n "${VNODE_COUNT}" ];  then
        VNODE_COUNT=2
    fi

    if  [ ! -n "${SUDO_PASSWORD}" ];  then
        echo "[Error] SUDO_PASSWORD is mandatory"
        Usage
        exit 1
    fi

}

################################
#
# Main Function
#
##############################
main(){
    local argc=("$@")
    local argv=$#

    if [ $argv  -eq 0 ];then
        Usage
        exit 1
    fi
    while [ "$1" != "" ]; do
        case $1 in
            ##########################
            # deploy opertion: parse arguments
            #########################
            deploy)
                parseOptions ${argc[@]:1} #elements from a[1]
                startInfrasimNodes
                break
                ;;
            ##########################
            # cleanup opertion: parse arguments
            #########################
            cleanup)
                parseOptions ${argc[@]:1} 
                cleanUpDockerContainer
                break
                ;;
            ##########################
            # --help 
            #########################
            -h | --help )
                Usage
                exit
                ;;
            *)  Usage
                exit 1
         esac
         shift
   done



}

################################
main $@
