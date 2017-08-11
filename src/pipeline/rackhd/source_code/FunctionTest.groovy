package pipeline.rackhd.source_code

def keepEnv(String library_dir, boolean keep_docker, boolean keep_env, int keep_minutes, String test_target, String test_name){
    def shareMethod = new pipeline.common.ShareMethod()
    String target_dir = test_target + "/" + test_name + "[$NODE_NAME]"
    if(keep_docker) {
        def docker_tag = JOB_NAME + "_" + test_target + "_" + test_name + ":" + BUILD_NUMBER
        docker_tag = docker_tag.replaceAll('/', '-')
        String docker_name = "my/test"
        shareMethod.saveDockerImage(library_dir, docker_name, docker_tag, "rackhdci", target_dir)
    }
    if(keep_env){
        def message = "Job Name: ${env.JOB_NAME} \n" + "Build Full URL: ${env.BUILD_URL} \n" + "Status: FAILURE \n" + "Stage: $test_target/$test_name \n" + "Node Name: $NODE_NAME \n" + "Reserve Duration: $keep_minutes minutes \n"
        echo "$message"
        slackSend "$message"
        sleep time: keep_minutes, unit: 'MINUTES'
    }
}

def runTest(String stack_type, String test_name, ArrayList<String> used_resources, Map manifest_dict, boolean keep_docker_on_failure, boolean keep_env_on_failure, int keep_minutes){
    def shareMethod = new pipeline.common.ShareMethod()
    String test_target = "source_code"
    def fit_configure = new pipeline.fit.FitConfigure(stack_type, test_target, test_name)
    fit_configure.configure()
    String node_name = ""
    String label_name = fit_configure.getLabel()
    try{
        lock(label:label_name,quantity:1){
            node_name = shareMethod.occupyAvailableLockedResource(label_name, used_resources)
            node(node_name){
                deleteDir()
                def manifest = new pipeline.common.Manifest()
                def fit = new pipeline.fit.FIT()
                def virtual_node = new pipeline.nodes.VirtualNode()
                def rackhd_deployer = new pipeline.rackhd.source_code.Deploy()
                String library_dir = "$WORKSPACE/on-build-config"
                shareMethod.checkoutOnBuildConfig(library_dir)
                String manifest_path = manifest.unstashManifest(manifest_dict, "$WORKSPACE")
                String rackhd_dir = manifest.checkoutTargetRepo(manifest_path, "RackHD", library_dir)
                boolean ignore_failure = false
                String target_dir = test_target + "/" + test_name + "[$NODE_NAME]"
                
                try{
                    // clean up rackhd and virtual nodes
                    rackhd_deployer.cleanUp(library_dir, ignore_failure)
                    virtual_node.cleanUp(library_dir, ignore_failure)
                    // deploy rackhd and virtual nodes
                    rackhd_deployer.deploy(library_dir, manifest_path)
                    virtual_node.deploy(library_dir)
                    virtual_node.startFetchLogs(library_dir, target_dir)
                    // run FIT test
                    fit.run(rackhd_dir, fit_configure)
                } catch(error){
                    keepEnv(library_dir, keep_docker_on_failure, keep_env_on_failure, keep_minutes, test_target, test_name)
                    error("[ERROR] Failed to run test $test_name against $test_target with error: $error")
                } finally{
                    // archive rackhd logs
                    rackhd_deployer.archiveLogsToTarget(library_dir, target_dir)
                    fit.archiveLogsToTarget(target_dir, fit_configure)
                    virtual_node.archiveLogsToTarget(target_dir)
                    // clean up rackhd and virtual nodes
                    ignore_failure = true
                    rackhd_deployer.cleanUp(library_dir, ignore_failure)
                    virtual_node.cleanUp(library_dir, ignore_failure)
                    virtual_node.stopFetchLogs(library_dir)
                    // archive logs of virtual nodes and FIT
                }
            }
        }
    } finally{
        used_resources.remove(node_name)
    }
}

return this
