pipeline {
    agent { label 'master' }
     environment {
         CURRENT_BRANCH = "null"
     }
    script { 
    switch(env.BRANCH_NAME) {            
         //There is case statement defined for 4 cases 
         // Each case statement section has a break condition to exit the loop 		
         case "DEV": 
            println("The branch is DEV");
            CURRENT_BRANCH="DEV"
            break; 
         case "SIT": 
            println("The branch is SIT"); 
            CURRENT_BRANCH="SIT"    
            break; 
         case "UAT": 
            println("The branch is UAT");
            CURRENT_BRANCH="UAT"
            break; 
         case "master": 
            println("The branch is master");
            CURRENT_BRANCH="master"
            break; 
         default: 
            println("The branch is unknown"); 
            CURRENT_BRANCH="XXX"
            break; 
      }
    }
    stages {
        stage('git pull') {
            steps {
            echo "The current branch is $CURRENT_BRANCH"
            }
        }
    }
}
