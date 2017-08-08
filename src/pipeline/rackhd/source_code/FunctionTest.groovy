package pipeline.rackhd.source_code
//import pipeline.fit.FIT

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
            dir("$target_dir"){
                sh """#!/bin/bash -e
                pushd $library_dir/src/pipeline/rackhd/source_code
                # export log of rackhd
                ./deploy.sh exportLog -p $SUDO_PASSWORD -w $WORKSPACE
                popd
                mv $WORKSPACE/build-log/*.log $target_dir
                """
            }
            archiveArtifacts "$target_dir/*.*, $target_dir/**/*.*"
        }
    } catch(error){
        echo "[WARNING]Caught error during archive artifact of rackhd to $target_dir: ${error}"
    }
}

def runTest(String stack_type, String test_name, ArrayList<String> used_resources, Map manifest_dict){
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
                try{
                    cleanUp(library_dir, ignore_failure)
                    deploy(library_dir, manifest_path)
                    //deployNodes()
                    fit.run(rackhd_dir, fit_configure)
                } finally{
                    String target_dir = "$WORKSPACE/" + test_target + "_" + test_name + "[$NODE_NAME]"
                    archiveLogsToTarget(library_dir, target_dir)
                    ignore_failure = true
                    cleanUp(library_dir, ignore_failure)
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
