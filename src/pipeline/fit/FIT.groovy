package pipeline.fit
def run(String rackhd_dir, Object fit_configure){
    withCredentials([
        usernamePassword(credentialsId: 'ff7ab8d2-e678-41ef-a46b-dd0e780030e1',
                         passwordVariable: 'SUDO_PASSWORD',
                         usernameVariable: 'SUDO_USER')])
    {
        String group = fit_configure.getGroup()
        String stack = fit_configure.getStack()
        String log_level = fit_configure.getLogLevel()
        String extra_options = fit_configure.getExtraOptions()
        try{
            sh """#!/bin/bash -ex
            pushd $rackhd_dir/test
            ./runFIT.sh -p $SUDO_PASSWORD -g "$group" -s "$stack" -v $log_level -e "$extra_options" -w $WORKSPACE
            popd
            """
        } finally{
            dir("$WORKSPACE"){
                junit 'xunit-reports/*.xml'
                stash name: "$target$name", includes: 'xunit-reports/*.xml, build-logs/*.log'
            }
        }
    }
}

def archiveLogsToTarget(String target_dir, Object fit_configure){
    try{
        String target = fit_configure.getTarget()
        String name = fit_configure.getName()
        dir(target_dir){
            unstash "$target$name"
        }
        archiveArtifacts "$target_dir/*.*, $target_dir/**/*.*"
    } catch(error){
        echo "[WARNING]Caught error during archive artifact for $name: $error"
    }
}

