//package pipeline.common
import java.io.File;



    String _on_build_config_dir
    String _on_build_config_stash_name="on_build_config_for_manifest"

    def Manifest( on_build_config_dir="" )
    {
        _on_build_config_dir = on_build_config_dir;
        if ( on_build_config_dir != "")
        {
            if ( false == fileExists("$_on_build_config_dir"  + File.separator + "README.md") ) {
                sh """#!/bin/bash -e
                      mkdir -p ${_on_build_config_dir}
                      pushd ${_on_build_config_dir}/../
                      git clone http://github.com/rackhd/on-build-config  ${_on_build_config_dir}
                      popd
                   """
            }
            stash name: "$_on_build_config_stash_name", includes: "$_on_build_config_dir"
        }

    }
     // it will output a manifest file({branch}-{day}), according to a template manifest (under build-release-tools/lib). and clone code to $builddir
     def generateManifest( String src_code_dir , String on_build_config_dir, String branch="master", String date="current", String timezone="+0800" ){

         if ( on_build_config_dir == "")
         {
            dir( "$on_build_config_dir/../")
            {
                    unstash "$_on_build_config_stash_name"
            }
         }
         sh """#!/bin/bash -ex
            ${on_build_config_dir}/build-release-tools/HWIMO-BUILD ${on_build_config_dir}/build-release-tools/application/generate_manifest.py \
            --branch $branch \
            --date $date \
            --timezone $timezone \
            --builddir $src_code_dir \
            --force \
            --jobs 8
         """

        fname = sh (
                     script: """#!/bin/bash -e
                     set +x
                     arrBranch=(  \$(echo $branch | tr "/" "\n" ) )
                     slicedBranch=\${arrBranch[-1]}
                     manifest_file=\$( find -maxdepth 1 -name "\$slicedBranch-[0-9]*" -printf "%f\n" )
                     echo \$(pwd)/\$manifest_file
                     """,
                     returnStdout: true
               )
         if ( fname == "" ){
            error("Manifest file generation failure !")
         }
         return fname;
    }

    //publish a manifest file to Bintray
    def publishManifest(String file_path, String on_build_config_dir ){
        withCredentials([
                usernamePassword(credentialsId: 'a94afe79-82f5-495a-877c-183567c51e0b',
                passwordVariable: 'BINTRAY_API_KEY',
                usernameVariable: 'BINTRAY_USERNAME')
        ]){

              String BINTRAY_SUBJECT = "rackhd"
              String BINTRAY_REPO = "binary"
              sh """#!/bin/bash -e
                    if [ ! -f $file_path ]; then
                        echo "[Error] $file_path not existing, abort! "
                    fi

                    file_name=\$(basename $file_path)

                    ${on_build_config_dir}/build-release-tools/pushToBintray.sh \
                    --user $BINTRAY_USERNAME \
                    --api_key $BINTRAY_API_KEY \
                    --subject $BINTRAY_SUBJECT \
                    --repo $BINTRAY_REPO \
                    --package manifest \
                    --version \$file_name \
                    --file_path $file_path
              """

       }
    }

    //download a manifest
    def downloadManifest(String url, String target_dir){
        fname= sh ( script:  """var=$url &&   echo \"\${var##*/}\"  """, returnStdout: true )
        sh 'wget --retry-connrefused --waitretry=1 --read-timeout=20 --timeout=15 -t 1 ' +  "$url" + ' -P ' + "${target_dir}"

        return target_dir +  File.separator + fname 
    }

    // stash a manifest file: to save the file(s) in Jenkins server for later usage from other vmslave
    def stashManifest(String stash_name, String manifest_path){
        manifest_path = manifest_path.replaceAll("//", "/");
        echo "DEBUG:  $stash_name :   $manifest_path "
        sh "ls -l $manifest_path "
        sh "touch /tmp/xxxxx.txt"
        echo "111111111"
        stash includes: "/tmp/xxxxx.txt", name: "test"
        echo "222222222"
        stash name: stash_name, includes: manifest_path
        echo "333333333"
        manifest_dict = [:]
        manifest_dict["stash_name"] = stash_name
        manifest_dict["stash_path"] = manifest_path
        return manifest_dict
    }

    // unstash a manifest file: to fetch the file(s) from Jenkins server
    def unstashManifest(Map manifest_dict, String target_dir){
        String stash_name    = manifest_dict["stash_name"]
        String manifest_path = manifest_dict["stash_path"]
        dir(target_dir){
            unstash "$stash_name"
        }
        manifest_path = target_dir + File.separator + manifest_path
        return manifest_path
    }

    // clone git repos and checkout branch accroding to manifest file
    // typically, target_dir= ${WORKSPACE}/build-deps
    def checkoutAccordingToManifest(String manifest_path, String target_dir, String on_build_config_dir)
    {
        
        sh """#!/bin/bash -ex
        pushd $on_build_config_dir
        ./build-release-tools/HWIMO-BUILD ./build-release-tools/application/reprove.py \
        --manifest ${manifest_path} \
        --builddir ${target_dir} \
        --jobs 8 \
        --force \
        checkout \
        packagerefs
        """

        
    }
    // checkout according to manifest, and return a specific repo's path
    def checkoutTargetRepo(String manifest_path, String target_dir, String on_build_config_dir, String repo_name ){
        checkoutAccordingToManifest( manifest_path,  target_dir, on_build_config_dir  )
        String repo_dir =   target_dir + File.separator + repo_name
        return repo_dir
    }



node {
    _on_build_config_dir="/tmp/x/on-build-config"
    _src_dir            ="/tmp/x/src"


//   fname = generateManifest( _src_dir ,_on_build_config_dir )
//  echo "$fname"
//   publishManifest( fname, _on_build_config_dir )


   df = downloadManifest( "https://dl.bintray.com/rackhd/binary/master-20170821", "/tmp/x" )
   echo "Downloaded $df"

   dict = stashManifest('stash_manifest', df   )
   node("vmslave21") {
            sh 'mkdir -p /tmp/peter'
            sh 'cd /tmp/peter && git clone https://github.com/rackhd/on-build-config.git '
            mfile = unstashManifest( dict, "/tmp/peter")
            checkoutAccordingToManifest( mfile, "/tmp/peter", "/tmp/peter/on-build-config" )
        }
}

