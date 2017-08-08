package pipeline.common
import java.io.File;

def downloadManifest(String url, String target){
    withCredentials([
            usernamePassword(credentialsId: 'a94afe79-82f5-495a-877c-183567c51e0b',
            passwordVariable: 'BINTRAY_API_KEY',
            usernameVariable: 'BINTRAY_USERNAME')
    ]){
        sh 'curl --user $BINTRAY_USERNAME:$BINTRAY_API_KEY --retry 5 --retry-delay 5 ' + "$url" + ' -o ' + "${target}"
    }
}

def stashManifest(String manifest_name, String manifest_path){
    stash name: "$manifest_name", includes: "$manifest_path"
    manifest_dict = [:]
    manifest_dict["stash_name"] = "manifest_name"
    manifest_dict["stash_path"] = "manifest_path"
    return manifest_dict
}

def unstashManifest(Map manifest_dict, String target_dir){
    String manifest_name = manifest_dict["stash_name"]
    String manifest_path = manifest_dict["stash_path"]
    dir(target_dir){
        unstash "$manifest_name"
    }
    manifest_path = target_dir + File.separator + manifest_path
    return manifest_path
}

def checkoutTargetRepo(String manifest_path, String repo_name, String on_build_config_dir){
    sh """#!/bin/bash -ex
    pushd $on_build_config_dir
    ./build-release-tools/HWIMO-BUILD ./build-release-tools/application/reprove.py \
    --manifest ${manifest_path} \
    --builddir ${WORKSPACE}/build-deps \
    --jobs 8 \
    --force \
    checkout \
    packagerefs
    
    """
    String repo_dir = "${WORKSPACE}/build-deps/$repo_name"
    return repo_dir
}
