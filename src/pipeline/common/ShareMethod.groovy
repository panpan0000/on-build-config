package pipeline.common

def checkout(String url, String branch, String targetDir){
    checkout(
    [$class: 'GitSCM', branches: [[name: branch]],
    extensions: [[$class: 'RelativeTargetDirectory', relativeTargetDir: targetDir]],
    userRemoteConfigs: [[url: url]]])
}
def checkout(String url, String branch){
    checkout(
    [$class: 'GitSCM', branches: [[name: branch]],
    userRemoteConfigs: [[url: url]]])
}

def checkout(String url){
    checkout(url, "master")
}

def checkoutOnBuildConfig(String target_dir){
    String scm_url = scm.getUserRemoteConfigs()[0].getUrl()
    if(scm_url.contains("on-build-config")){
        dir(target_dir){
            checkout scm
        }
    }else {
        checkout("https://github.com/RackHD/on-build-config", master, target_dir)
    }
}

def getLockedResourceName(String label_name){
    // Get the resource name whose label contains the parameter label_name
    // The locked resources of the build
    def resources=org.jenkins.plugins.lockableresources.LockableResourcesManager.class.get().getResourcesFromBuild(currentBuild.getRawBuild())
    def resources_name=[]
    for(int i=0;i<resources.size();i++){
        String labels = resources[i].getLabels();
        List label_names = Arrays.asList(labels.split("\\s+"));
        for(int j=0;j<label_names.size();j++){
            if(label_names[j]==label_name){
                resources_name.add(resources[i].getName());
            }
        }
    }
    return resources_name
}

def occupyAvailableLockedResource(String label_name, ArrayList<String> used_resources){
     // The locked resources whose label contains the parameter label_name
    resources = getLockedResourceName(label_name)
    def available_resources = resources - used_resources
    if(available_resources.size > 0){
        used_resources.add(available_resources[0])
        String resource_name = available_resources[0]
        return resource_name
    }
    else{
        error("There is no available resources for $label_name")
    }
}

def parseJsonResource(String resource_path){
    def json_text = libraryResource(resource_path)
    def props = readJSON text: json_text
    echo "${props}"
    return props
}

def saveDockerImage(String library_dir, String docker_name, String docker_tag, String target_docker_repo, String target_output_dir){
    withCredentials([
        usernamePassword(credentialsId: 'ff7ab8d2-e678-41ef-a46b-dd0e780030e1',
                         passwordVariable: 'SUDO_PASSWORD',
                         usernameVariable: 'SUDO_USER'),
        usernamePassword(credentialsId: 'rackhd-ci-docker-hub',
                         passwordVariable: 'DOCKERHUB_PASS',
                         usernameVariable: 'DOCKERHUB_USER')
    ]){
        dir("$target_output_dir"){
            sh """#!/bin/bash -ex
            current_dir=`pwd`
            pushd $library_dir/src/pipeline/common
            ./save_docker.sh -s $SUDO_PASSWORD -u $DOCKERHUB_USER -p $DOCKERHUB_PASS -r $target_docker_repo -n $docker_name -t $docker_tag -o $current_dir
            popd
            """
            archiveArtifacts "*.log"
        }
    }
}
