node(build_ova_node){ws{
    lock("packer_bri"){
        timestamps{
            withEnv([
                "RACKHD_COMMIT=${env.RACKHD_COMMIT}",
                "RACKHD_VERSION=${env.RACKHD_VERSION}",
                "IS_OFFICIAL_RELEASE=${env.IS_OFFICIAL_RELEASE}",
                "OS_VER=${env.OS_VER}",
                "BUILD_TYPE=vmware",
                "STAGE_REPO_NAME=${env.STAGE_REPO_NAME}",
                "DEB_COMPONENT=${env.DEB_COMPONENT}",
                "DEB_DISTRIBUTION=trusty"]) { 
                def current_workspace = pwd()
                deleteDir()
                def shareMethod
                dir("Build_OVA_JFiles"){
                    checkout scm
                    shareMethod = load("jobs/shareMethod.groovy")
                }
                def url = "https://github.com/RackHD/RackHD.git"
                def branch = "${env.RACKHD_COMMIT}"
                def targetDir = "build"
                shareMethod.checkout(url, branch, targetDir)

                timeout(180){
                    withEnv(["WORKSPACE=${current_workspace}"]){
                        sh './Build_OVA_JFiles/jobs/build_ova/build_ova.sh'
                    }
                }
                archiveArtifacts 'build/packer/*.ova, build/packer/*.log, build/packer/*.md5, build/packer/*.sha'
                stash name: 'ova', includes: 'build/packer/*.ova'
                env.OVA_WORKSPACE="${current_workspace}"
                echo "${env.OVA_WORKSPACE}"
            }
        }
    }
}}

