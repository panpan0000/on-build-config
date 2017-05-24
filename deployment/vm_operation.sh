#!/bin/sh +x
Usage()
{
    echo "this script is used to operate VM, including power_on, power_off and delete"
    return 0
}

vm_getid() #get the id of VM via the name, RE is supported, the return value is a string
{
    vm_name=$1
    if [ $vm_name = "all" ];then
        vm_name="[0-9a-zA-Z_]\{1,\}"
        id_string=`vim-cmd vmsvc/getallvms | grep -w "${vm_name}" | awk '{print $1}' | tail -n+2` #need to remove the first line
    else
        id_string=`vim-cmd vmsvc/getallvms | grep -w "${vm_name}" | awk '{print $1}'`
    fi
    if [ $? -ne 0 ]; then
        return -1
    fi
# below three lines are commented out by Peter. they don't make sense
#    if [ -z $id_string ];then
#        return 1
#    fi
    echo ${id_string} # echo the result as a return value
    return 0
}

vm_getname() #get the name of VM via ID, return ID if fails
{
    vm_id=$1
    vm_name=`vim-cmd vmsvc/getallvms | grep -w ${vm_id} | awk '{print $2}'`
    if [ -z $vm_name ];then
        echo $vm_id
        return 1
    fi
    echo $vm_name
    return 0
}


take_snapshot() # parameter: vm_id
{
    duration=$1
    shift 1
    for vmid in $@
    do
        vm_name=`vm_getname $vmid`
        SNAPSHOTNAME=${vm_name}$(date +%Y-%m-%d:%H:%M:%S)
        echo "[ESX] Creating Snapshot for $vm_name, named $SNAPSHOTNAME"
        vim-cmd  vmsvc/snapshot.create $vmid   $SNAPSHOTNAME
        sleep $duration 
    done
}

revert_last_snapshot() #parameter: vm_id
{
    duration=$1
    shift 1
    for vmid in $@
    do
        vm_name=`vm_getname $vmid`
        last_snapshot_id=$(  vim-cmd  vmsvc/snapshot.get ${vmid}|   grep "Snapshot Id"|  tail -1|awk '{print $NF}')
        last_snapshot_name=$(vim-cmd  vmsvc/snapshot.get ${vmid}| grep "Snapshot Name"|  tail -1|awk '{print $NF}')
        if [ "$last_snapshot_id" == "" ]; then
            echo "[ESX] no Snapshot ever taken. force take a snapshot"
            take_snapshot $duration $vmid
            last_snapshot_id=$(  vim-cmd  vmsvc/snapshot.get ${vmid}|   grep "Snapshot Id"|  tail -1|awk '{print $NF}')
            last_snapshot_name=$(vim-cmd  vmsvc/snapshot.get ${vmid}| grep "Snapshot Name"|  tail -1|awk '{print $NF}')
        fi
        echo "[ESX] Revert VM ${vm_name} to last snapshot : ${last_snapshot_name} "
        suppressPowerOn=false
        vim-cmd  vmsvc/snapshot.revert  $vmid   $last_snapshot_id $suppressPowerOn
        sleep $duration 
    done

}


power_action() #id_string action(on/off/reset)
{
    action=$1
    duration=$2
    shift 2
    for id in $@
    do
        state=`vim-cmd vmsvc/power.getstate $id | grep "^Powered" | awk '{print $2}'`
        vm_name=`vm_getname $id`
        if [ $action = "reset" -a $state = "off" ];then
            echo "$vm_name current state is off, changing action to power_on instead of reset"
            action="on"
        fi 
        if [ $state = $action ];then
            echo "$vm_name current state has been $state, no need to do power_$action"
            continue
        else
            echo "$vm_name current state is $state, will do power_$action"
        fi
        vim-cmd vmsvc/power.${action} $id 2>&1 > /dev/null
        if [ $? -ne 0 ];then
            echo "ERROR: power_$action VM $vm_name fails"
            continue
        fi
        state=`vim-cmd vmsvc/power.getstate $id | grep "^Powered" | awk '{print $2}'`
        if [ $action != reset -a $state != $action ];then
            echo "ERROR: $vm_name power_$action fails"
        else
            echo "$vm_name power_$action successfully"
        fi
        sleep $duration
    done
}

delete_action() #id_string
{
    duration=$1
    shift 1
    for id in $@
    do
        vm_name=`vm_getname $id`
        if [ $? -ne 0 ]; then
            echo "ERROR: can't get the exact VM name via $id"
            continue
        fi
        state=`vim-cmd vmsvc/power.getstate $id | grep "^Powered" | awk '{print $2}'`
        echo "VM $vm_name current state is $state, start to be deleted..."
        if [ $state = "on" ];then
            vim-cmd vmsvc/power.off $id 2>&1 > /dev/null
            if [ $? -ne 0 ];then
                echo "ERROR: VM $vm_name power off fails, so can't be deleted"
                continue
            fi
        fi
        vim-cmd vmsvc/destroy  $id 2>&1 > /dev/null
        if [ $? -ne 0 ];then
            echo "ERROR: VM $vm_name delete fails"
            continue
        fi
        echo "VM $vm_name has been deleted successfully!"
        sleep $duration
    done
}

shift_num=0 #used to shift the handled arguments such as -b
while getopts "a:" optname
do
    case "$optname" in
        "a")vm_action=$OPTARG
            shift_num=`expr $shift_num + 2`
            ;;
        "?")echo "invalid argument"
            exit 1
            ;;
    esac
done

shift $shift_num

server_ip=$1
echo "start to $vm_action VM(s) on server $server_ip"
if [ $# -lt 3 ];then echo "ERROR: there is no duration or VM name for server $server_ip";fi
duration=$2
shift 2

for vm in $@
do
    vm_ids=`vm_getid $vm`
    echo "[DEBUG] vm_ids==${vm_ids}"
    if [ $? -ne 0 ];then
        echo "ERROR: can't get the VM ID via the name ${vm}"
        continue
    fi
    case $vm_action in
        "vm_getid")  
            ret_msg=$(vm_getid $vm )
            if [ -n "$ret_msg" ]; then
                 echo "return_from_vm_getid $ret_msg"
             else
                 echo "return_from_vm_getid : Not Found "
             fi
            ;;
        "take_snapshot") take_snapshot $duration $vm_ids;;
        "revert_last_snapshot") revert_last_snapshot $duration $vm_ids;;
        "power_on") power_action "on" $duration $vm_ids;;
        "power_off") power_action "off" $duration $vm_ids;;
        "reset") power_action "reset" $duration $vm_ids;;
        "delete") delete_action $duration $vm_ids;;
    esac
done
