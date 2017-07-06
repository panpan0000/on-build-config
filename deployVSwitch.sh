#!/bin/bash -e
#############################################
#
# Global Variable
############################################
OV_BRIDGE=ovs-br0

#############################################
#
# Usage
############################################
Usage(){
    set +x
    echo "Function: This script is used to create a virtual switch $OV_BRIDGE with open-vswitch.
                    It requires there is a NIC with IP 172.31.128.x
                    The script will move the IP of the NIC to $OV_BRIDGE and set the IP of the NIC as 0"
    echo "Usage: $0 [OPTIONS] [ARGUMENTS]"
    echo "  OPTIONS:"
    echo "    --help : give this help list"
    echo "    cleanUp: remove the virtual switch $OV_BRIDGE created by the script"
    echo "    deploy : create a virtual switch $OV_BRIDGE 
                       set its IP as the original IP of the NIC whose IP is 172.31.128.x"
    echo "  ARGUMENTS:"
    echo "    -p     : the password of current user with root privilege"
    set -x
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
# Delete bridge and restore IP
#
#####################################
restore_host_network(){
    echo "Restore NIC configurations and delete old open vswitch bridge..."
    set +e
    # delete the bridge created by open vswitch
    local bridges=$( echo $SUDO_PASSWORD |sudo -S  ovs-vsctl list-br| grep $OV_BRIDGE )
    if [ "$bridges" != "" ];  then
         local DHCP_NIC=$( echo $SUDO_PASSWORD |sudo -S  ovs-vsctl list-ports ${bridges} | head -n1 )
         local original_ip=$(ifconfig ${bridges} | awk '/inet addr/{print substr($2,6)}')
         echo $SUDO_PASSWORD |sudo -S ovs-vsctl del-br $bridges
         echo $SUDO_PASSWORD |sudo -S ifconfig $DHCP_NIC $original_ip
         echo $SUDO_PASSWORD |sudo -S ifconfig $DHCP_NIC -promisc
    fi
    set -e
}

#######################################
#
# Parse and check arguments
#
#####################################
parseArguments(){
    while [ "$1" != "" ]; do
        case $1 in
            -p | --SUDO_PASSWORD )          shift
                                            SUDO_PASSWORD=$1
                                            ;;
            * )                             Usage
                                            exit 1
        esac
        shift
    done
    if [ ! -n "$SUDO_PASSWORD" ]; then
        echo "The argument -p is required"
        exit 1
    fi
}

#####################################
#
# Main
#
###################################
case "$1" in
  cleanUp)
      shift
      parseArguments $@
      restore_host_network
  ;;

  deploy)
      shift
      parseArguments $@
      setup_host_network 
  ;;

  -h | --help)
      Usage
      exit 0
  ;;

  *)
      Usage
      exit 1
  ;;

esac

