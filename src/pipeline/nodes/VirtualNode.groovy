package pipeline.nodes

def getVNodes(){
    def VCOMPUTE = [:]
    def config_path = "pipeline/nodes/virtual_nodes.json"
    def shareMethod = new pipeline.common.ShareMethod()
    def vnodes = shareMethod.parseJsonResource(config_path)
    def names = vnodes.keySet()
    for(name in names){
        int node_count = vnodes[name]["count"]
        String ova_path = vnodes[name]["ova_path"]
        for(int i=0;i<node_count;i++){
            VCOMPUTE["$name$i"] = ["name":"$name$i","ova_path":"$ova_path"]
        }
    }
    return VCOMPUTE
}

def deploy(String library_dir){
    withEnv([
        "ESXI_HOST=${env.ESXI_HOST}", // environment from node configure
        "DATASTORE=${env.DATASTORE}",
        "NIC=${env.NIC}"
    ]){
        withCredentials([
            usernamePassword(credentialsId: 'ESXI_CREDS',
                             passwordVariable: 'ESXI_PASS',
                             usernameVariable: 'ESXI_USER')
        ]) {
            def VCOMPUTE = getVNodes()
            def names = VCOMPUTE.keySet()
            for(name in names){
                def vnode_name = "$NODE_NAME-" + VCOMPUTE[name]["name"]
                def switch_name = "$NODE_NAME-switch"
                def ova_path = VCOMPUTE[name]["ova_path"]
                sh """#!/bin/bash -ex
                pushd $library_dir/deployment
                ./deploy_vnodes.sh deploy -h "$ESXI_HOST" -u "$ESXI_USER" -p "$ESXI_PASS" -s "$switch_name" -n "$NIC" -d "$DATASTORE" -m "" -v "$vnode_name" -o "$ova_path" -b $library_dir
                popd
                """
            }
        }
    }
}

def cleanUp(String library_dir, boolean ignore_failure){
    try{
        withEnv([
            "ESXI_HOST=${env.ESXI_HOST}"
        ]){
            withCredentials([
                usernamePassword(credentialsId: 'ESXI_CREDS',
                                 passwordVariable: 'ESXI_PASS',
                                 usernameVariable: 'ESXI_USER')
            ]) {
                def VCOMPUTE = getVNodes()
                def names = VCOMPUTE.keySet()
                for(name in names){
                    def vnode_name = "$NODE_NAME-" + VCOMPUTE[name]["name"]
                    sh """#!/bin/bash -ex
                    pushd $library_dir/deployment
                    ./deploy_vnodes.sh cleanUp -h "$ESXI_HOST" -u "$ESXI_USER" -p "$ESXI_PASS" -v "$vnode_name" -b $library_dir
                    popd
                    """
                }
            }
        }
    }catch(error){
        if(ignore_failure){
            echo "[WARNING]: Failed to clean up virtual nodes with error: ${error}"
        } else{
            error("[ERROR]: Failed to clean up virtual nodes with error: ${error}")
        }
    }
}

def startFetchLogs(String library_dir, String target_dir){
    try{
        withCredentials([
             usernamePassword(credentialsId: 'BMC_VNODE_CREDS',
                             passwordVariable: 'BMC_VNODE_PASSWORD',
                             usernameVariable: 'BMC_VNODE_USER')
        ]) {
            dir(target_dir){
                sh """#!/bin/bash -ex
                export current_dir=`pwd`
                pushd $library_dir/deployment
                ./fetch_vnodes_log.sh start --LOG_DIR $current_dir --BMC_ACCOUNT_LIST "$BMC_VNODE_USER:$BMC_VNODE_PASSWORD" --ON_BUILD_CONFIG_DIR $library_dir
                popd
                """
            }
        }
    } catch(error){
        echo "[WARNING] Failed to fetch logs of virtual nodes with error: $error"
    }
}

def stopFetchLogs(String library_dir){
    try{
        sh """#!/bin/bash -x
        set +e
        pushd $library_dir/deployment
        ./fetch_vnodes_log.sh stop
        popd
        """
    } catch(error){
        echo "[WARNING] Failed to stop fetching logs of virtual nodes with error: $error"
    }
}

def archiveLogsToTarget(String target_dir){
    def shareMethod = new pipeline.common.ShareMethod()
    shareMethod.archiveTargetLogs(target_dir)
}
