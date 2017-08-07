package pipeline.common

def downloadManifest(String url, String target){
    withCredentials([
            usernamePassword(credentialsId: 'a94afe79-82f5-495a-877c-183567c51e0b',
            passwordVariable: 'BINTRAY_API_KEY',
            usernameVariable: 'BINTRAY_USERNAME')
    ]){
        sh 'curl --user $BINTRAY_USERNAME:$BINTRAY_API_KEY --retry 5 --retry-delay 5 ' + "$url" + ' -o ' + "${target}"
    }
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
