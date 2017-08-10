package pipeline.rackhd.source_code

def deploy(String library_dir, String manifest_path){
    /*
    Deploy rackhd
    :library_dir: the directory of on-build-config
    :manifest_path: the absolute path of manifest file
    */
    withCredentials([
        usernamePassword(credentialsId: 'ff7ab8d2-e678-41ef-a46b-dd0e780030e1',
                         passwordVariable: 'SUDO_PASSWORD',
                         usernameVariable: 'SUDO_USER')])
    {
	step ([$class: 'CopyArtifact',
                projectName: 'Docker_Image_Build',
                target: "$WORKSPACE"])
        sh """#!/bin/bash -ex
        pushd $library_dir/src/pipeline/rackhd/source_code
        # Deploy image-service docker container which is from base image
        ./deploy.sh deploy -w $WORKSPACE -f $manifest_path -p $SUDO_PASSWORD -b $library_dir -i $WORKSPACE/rackhd_pipeline_docker.tar
        popd
        """
    }
}

def cleanUp(String library_dir, boolean ignore_failure){
    try{
        withCredentials([
            usernamePassword(credentialsId: 'ff7ab8d2-e678-41ef-a46b-dd0e780030e1',
                             passwordVariable: 'SUDO_PASSWORD',
                             usernameVariable: 'SUDO_USER')])
        {
            sh """#!/bin/bash -e
            pushd $library_dir/src/pipeline/rackhd/source_code
            # Clean up exsiting rackhd ci docker containers and images
            ./deploy.sh cleanUp -p $SUDO_PASSWORD
            popd
            """
        } 
    }catch(error){
        if(ignore_failure){
            echo "[WARNING]: Failed to clean up rackhd with error: ${error}"
        } else{
            error("[ERROR]: Failed to clean up rackhd with error: ${error}")
        }
    }
}

def archiveLogsToTarget(String library_dir, String target_dir){
    try{
        withCredentials([
            usernamePassword(credentialsId: 'ff7ab8d2-e678-41ef-a46b-dd0e780030e1',
                             passwordVariable: 'SUDO_PASSWORD',
                             usernameVariable: 'SUDO_USER')])
        {
            dir(target_dir){
                sh """#!/bin/bash -e
                pushd $library_dir/src/pipeline/rackhd/source_code
                # export log of rackhd
                ./deploy.sh exportLog -p $SUDO_PASSWORD -w $WORKSPACE
                popd
                pushd $WORKSPACE
                mv build-log/*.log $target_dir
                popd
                """
            }
            archiveArtifacts "$target_dir/*.*, $target_dir/**/*.*"
        }
    } catch(error){
        echo "[WARNING]Caught error during archive artifact of rackhd to $target_dir: ${error}"
    }
}

def keepFailureEnv(String library_dir, boolean keep_docker, boolean keep_env, int keep_minutes, String test_target, String test_name){
    String target_dir = test_target + "/" + test_name + "[$NODE_NAME]"
    if(keep_docker) {
        def docker_tag = JOB_NAME + "_" + test_target + "_" + test_name + ":" + BUILD_NUMBER
        sh """#!/bin/bash -x
        set +e
        pushd $library_dir
        ./src/pipeline/rackhd/source_code/save_docker.sh/save_docker.sh $docker_tag $target_dir
        popd
        """
        archiveArtifacts "$target_dir/*.*"
    }
    if(keep_env){
        def message = "Job Name: ${env.JOB_NAME} \n" + "Build Full URL: ${env.BUILD_URL} \n" + "Status: FAILURE \n" + "Stage: $test_target/$test_name \n" + "Node Name: $NODE_NAME \n" + "Reserve Duration: $keep_minutes minutes \n"
        echo "$message"
        slackSend "$message"
        sleep time: keep_minutes, unit: 'MINUTES'
    }
}

def runTest(String stack_type, String test_name, ArrayList<String> used_resources, Map manifest_dict, boolean keep_docker_on_failure, boolean keep_env_on_failure, int keep_minutes){
    def manifest = new pipeline.common.Manifest()
    def shareMethod = new pipeline.common.ShareMethod()
    def fit = new pipeline.fit.FIT()
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
                String library_dir = "$WORKSPACE/on-build-config"
                shareMethod.checkoutOnBuildConfig(library_dir)
                String manifest_path = manifest.unstashManifest(manifest_dict, "$WORKSPACE")
                String rackhd_dir = manifest.checkoutTargetRepo(manifest_path, "RackHD", library_dir)
                boolean ignore_failure = false
                String target_dir = test_target + "/" + test_name + "[$NODE_NAME]"
                try{
                    cleanUp(library_dir, ignore_failure)
                    deploy(library_dir, manifest_path)
                    //deployNodes()
                    fit.run(rackhd_dir, fit_configure)
                } catch(error){
                    keepFailureEnv(library_dir, keep_docker_on_failure, keep_env_on_failure, keep_minutes, test_target, test_name)
                    error("[ERROR] Failed to run test $test_name against $test_target with error: $error")
                } finally{
                    archiveLogsToTarget(library_dir, target_dir)
                    ignore_failure = true
                    cleanUp(library_dir, ignore_failure)
                    fit.archiveLogsToTarget(target_dir, fit_configure)
                    //archiveNodesLogToTarget(library_dir, target_dir)
                    //cleanUpNodes(library_dir)
                }
            }
        }
    } finally{
        used_resources.remove(node_name)
    }
}

return this
