#!/bin/bash -ex
export VCOMPUTE=("${NODE_NAME}-Rinjin1","${NODE_NAME}-Rinjin2","${NODE_NAME}-Quanta")

VCOMPUTE="${VCOMPUTE}"
if [ -z "${VCOMPUTE}" ]; then
  VCOMPUTE=("jvm-Quanta_T41-1" "jvm-vRinjin-1" "jvm-vRinjin-2")
fi


nodesDelete() {
    set +e
    local infrasim_dir=${WORKSPACE}/infrasim
    pushd $infrasim_dir
    # destroy previous running InfraSIM
    for id in $(seq 1 ${VNODE_COUNT}); do
        local n=node${id}
        sudo infrasim node destroy ${n}
    done
    set -e

}


cleanupENVProcess() {
  # Kill possible socat process left by ova-post-smoke-test
  # eliminate the effect to other test
  socat_process=`ps -ef | grep socat | grep -v grep | awk '{print $2}' | xargs`
  if [ -n "$socat_process" ]; then
    kill $socat_process
  fi
}

clean_running_containers() {
    local containers=$(docker ps -a -q)
    if [ "$containers" != "" ]; then
        echo "Clean Up containers : " ${containers}
        docker stop ${containers}
        docker rm  ${containers}
    fi
}

if [ "$SKIP_PREP_DEP" == false ] ; then
  # Prepare the latest dependent repos to be shared with vagrant
  nodesDelete
  cleanupENVProcess
  clean_running_containers
fi
