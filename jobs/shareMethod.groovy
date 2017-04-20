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

def getLockedResourceName(resources,label_name){
    // Get the resource name whose label contains the parameter label_name
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

def buildAndPublish(){
    // retry times for package build and images build to avoid failing caused by network
    int retry_times = 3
    stage("Packages Build"){
        retry(retry_times){
            load("jobs/build_debian/build_debian.groovy")
        }
    }
    // lock a docker resource from build to release
    lock(label:"docker",quantity:1){
        def lock_resources=org.jenkins.plugins.lockableresources.LockableResourcesManager.class.get().getResourcesFromBuild(currentBuild.getRawBuild())       
        docker_resources_name = getLockedResourceName(lock_resources,"docker")
        if(docker_resources_name.size>0){
            env.build_docker_node = docker_resources_name[0]
        }
        else{
            echo "Failed to find resource with label docker"
            currentBuild.result="FAILURE"
        }

        stage("Images Build"){
            parallel 'vagrant build':{
                retry(retry_times){
                    load("jobs/build_vagrant/build_vagrant.groovy")
                }
            }, 'ova build':{
                retry(retry_times){
                    load("jobs/build_ova/build_ova.groovy")
                }
            }, 'build docker':{
                retry(retry_times){
                    load("jobs/build_docker/build_docker.groovy")
                }
            }
        }

        stage("Post Test"){
            parallel 'vagrant post test':{
                load("jobs/build_vagrant/vagrant_post_test.groovy")
            }, 'ova post test':{
                load("jobs/build_ova/ova_post_test.groovy")
            }, 'docker post test':{
                load("jobs/build_docker/docker_post_test.groovy")
            }
        }

        stage("Publish"){
            parallel 'Publish Debian':{
                load("jobs/release/release_debian.groovy")
            }, 'Publish Vagrant':{
                load("jobs/release/release_vagrant.groovy")
            }, 'Publish Docker':{
                load("jobs/release/release_docker.groovy")
            }, 'Publish NPM':{
                load("jobs/release/release_npm.groovy")
            }
        }
    }
}

def sendResult(boolean sendJenkinsBuildResults, boolean sendTestResults){
    stage("Send Test Result"){
        try{
            if ("${currentBuild.result}" == null || "${currentBuild.result}" == "null"){
                currentBuild.result = "SUCCESS"
            }
            step([$class: 'VTestResultsAnalyzerStep', sendJenkinsBuildResults: sendJenkinsBuildResults, sendTestResults: sendTestResults])
        } catch(error){
            echo "Caught: ${error}"
        }
    }
}

return this
