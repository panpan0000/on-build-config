
class FunctionTestBase implements Serializable {
    def runtime  //to become a point to Script class instance . lower case 

    def runTests( function_test){
        def test_branches = generate_test_branch(function_test)
        runtime.echo "end of generate_test_branch"
        if(test_branches.size() > 0){
            try{
                runtime.parallel test_branches
            } finally{
                archiveArtifacts(function_test)
            }
        }

    }

    def archiveArtifacts ( f_test)
    {
        runtime.echo "archiveArtifacts........."
    }

    def generate_test_branch(   function_test ){
        def test_branches = [:]
        runtime.node{
            runtime.deleteDir()
            runtime.checkout runtime.scm
            def shareMethod = runtime.load("jobs/ShareMethod.groovy") 
            runtime.echo "Load shareMethod Done."
            def ALL_TESTS = function_test.getAllTests()//xxxxxxxxxxxxxxxxxxxxxx
            def TESTS = "${runtime.env.TESTS}"
            if(TESTS == "null" || TESTS == "" || TESTS == null){
                print "no test need to run"
                return 
                
            }

            def test_stack = my_test_stack()
            List tests_group = Arrays.asList(TESTS.split(','))
            for(int i=0; i<tests_group.size(); i++){
                def test_name = tests_group[i]
                def label_name=ALL_TESTS[test_name]["label"]
                def test_group = ALL_TESTS[test_name]["TEST_GROUP"]
                def run_fit_test = ALL_TESTS[test_name]["RUN_FIT_TEST"]
                def extra_hw = ALL_TESTS[test_name]["EXTRA_HW"]
                runtime.echo "test_branches[$test_name] added"
                test_branches["$test_name"] = testBranch.curry( function_test , shareMethod,   test_group , run_fit_test, extra_hw, label_name, 15+i ) // create a new Closure by curry
            }


        }
        return test_branches
    }

    Closure testBranch={ function_test, shareMethod,  test_group , run_fit_test, extra_hw, label_name, my_test_id  ->
        runtime.echo "testBranch  $test_group , label_name = $label_name "
        String node_name=""
        // def used_resources = function_test.getUsedResources()//xxxxxxxxxxxxxxxx
        //runtime.echo "used_resources = $used_resources"
        try{
           runtime.lock(label:label_name,quantity:1){
                // Occupy an avaliable resource which contains the label
                // FIXME: I think the shareMethod should be implemented with Closure and delegaion
                //node_name = shareMethod.occupyAvailableLockedResource(label_name, used_resources)
                runtime.echo "Get into Try{}"

                node_name="vmslave$my_test_id"
                runtime.echo "running on $node_name"

                runtime.node(node_name){
                    runtime.deleteDir()// FIXME, it stucks here. ????????????????????????????????????????????????????????
                    runtime.dir("build-config"){
                         checkout runtime.scm
                    }
                    
                    deployRackHD()
                    runTest()
                }
           }
        } finally{
            //used_resources.remove(node_name)
        }
 
    }
}

class sourceBaseTest extends FunctionTestBase{
    def TEST_TYPE = "manifest"
    def my_test_stack = {"-stack docker_local_run"}

    def deployRackHD = {
        runtime.withEnv([
            "SKIP_PREP_DEP=false",
            "XXX=XXXXXXX"])
        {
            runtime.withCredentials([
               runtime.usernamePassword(credentialsId: 'ff7ab8d2-e678-41ef-a46b-dd0e780030e1',
                                     passwordVariable: 'SUDO_PASSWORD',
                                     usernameVariable: 'SUDO_USER')]
            )
            {
               runtime.sh '''
               set -x
               echo "$SKIP_PREP_DEP"
               echo "$XXX"
               '''  
            }
        }


    }
    def runTest = {
         runtime.sh '''
         echo "I'm sourceBaseTest::runTest()"
         '''
    }
    

}



node{
    deleteDir()
    checkout scm
    echo "111111"
    a=new sourceBaseTest(runtime:this)
    echo "22222"
    
    def function_test = load("jobs/FunctionTest/FunctionTest.groovy")
    a.runTests( function_test )

}

