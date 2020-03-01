pipeline {
    agent { label 'master' } 
    stages {
        stage('detect env'){
            steps {
                    script { 
                      switch(env.BRANCH_NAME) {            
                         //There is case statement defined for 4 cases 
                         // Each case statement section has a break condition to exit the loop 		
                         case "DEV": 
                            println("The branch is DEV");
                            CURRENT_BRANCH="DEV"
                            connection_string="(DESCRIPTION = (ADDRESS = (PROTOCOL = TCP)(HOST = localhost)(PORT = 1523)) (CONNECT_DATA = (SERVER = DEDICATED) (SERVICE_NAME = ORCLPDB1.localdomain)))"
                            usr="hr"
                            pwd="hr"
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
            }
        }
        stage('git pull') {
            steps {
            echo "current direct"
            echo "The current branch is $CURRENT_BRANCH"
            sh "pwd"
            sh "git pull"
            sh "mkdir -p ./ARTIFACTS/'$CURRENT_BRANCH'_DEPLOYMENT &&  cp $(git diff HEAD~1..HEAD --diff-filter=d --name-only 'TABLES/*.sql') '$_'"
            sh "mkdir -p ./ARTIFACTS/'$CURRENT_BRANCH'_DEPLOYMENT &&  cp $(git diff HEAD~1..HEAD --diff-filter=d --name-only 'VIEWS/*.sql') '$_'"
            sh "mkdir -p ./ARTIFACTS/'$CURRENT_BRANCH'_DEPLOYMENT &&  cp $(git diff HEAD~1..HEAD --diff-filter=d --name-only 'FUNCTIONS/*.sql') '$_'"
            sh "mkdir -p ./ARTIFACTS/'$CURRENT_BRANCH'_DEPLOYMENT &&  cp $(git diff HEAD~1..HEAD --diff-filter=d --name-only 'PROCEDURES/*.sql') '$_'"
            sh "mkdir -p ./ARTIFACTS/'$CURRENT_BRANCH'_DEPLOYMENT &&  cp $(git diff HEAD~1..HEAD --diff-filter=d --name-only 'TRIGGERS/*.sql') '$_'"
            sh "mkdir -p ./ARTIFACTS/'$CURRENT_BRANCH'_DEPLOYMENT &&  cp $(git diff HEAD~1..HEAD --diff-filter=d --name-only 'PACKAGES/*.sql') '$_'"
            sh "git status"
            }
        }
    }
}
