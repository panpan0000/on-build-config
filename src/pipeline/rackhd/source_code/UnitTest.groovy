package pipeline.rackhd.source_code

def runTest(manifest_dict, repo_name){
    /*
    manifest is a map contains manifest stash name and stash path:
    {"stash_name":xxx,
     "stash_path":xxx}
    repo_name is a String which is the name of the repository 
    */
    def shareMethod = new pipeline.common.ShareMethod()
    String label_name="unittest"
    lock(label:label_name,quantity:1){
        node_name = shareMethod.occupyAvailableLockedResource(label_name, [])
        node(node_name){
            deleteDir()
            String on_build_config_dir = "$WORKSPACE/on-build-config"
            shareMethod.checkoutOnBuildConfig(on_build_config_dir)
            String manifest_name = manifest_dict["stash_name"]
            unstash "$manifest_name"
            String manifest_path = "$WORKSPACE/" + manifest_dict["stash_path"]
            def manifest = new pipeline.common.Manifest()
            String repo_dir = manifest.checkoutTargetRepo(manifest_path, repo_name, on_build_config_dir)
            try{
                sh """#!/bin/bash -ex
                pushd $repo_dir
                ./HWIMO-TEST
                popd
                """
            } finally{
                dir(repo_dir){
                    junit "*.xml"
                    archiveArtifacts "*.xml"
                }
            }
        }
    }
}

return this

