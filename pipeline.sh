pipeline {
    agent any
	parameters {
       string(name: 'branchName', defaultValue: 'must_change_this', description: 'Branch to build (must start with "sprint-" followed by numbers only)')
		choice(name: 'environment', choices: ['dev', 'qa'], description: 'Select environment for build')
		string(name: 'imageTag', defaultValue: 'latest', description: 'Docker image tag for ECR')
    }
	environment {
		// Enable / Disable stages flags
		sonarStageBool = false
		unitTestStageBool = false						  

		// Checkout
		repoUrl = 'https://git-codecommit.us-east-1.amazonaws.com/v1/repos/phoenix'
		rootFolder = 'mt'
		subFolder = 'phoenix-microservice'

		// SonarQube
// 		sonarqGate = 'false'
// 		sonarCommand = 'clean verify -Dspring.profiles.active=sonar org.sonarsource.scanner.maven:sonar-maven-plugin:3.6.0.1398:sonar'
// 		sonarProjectName = 'Shared Services Kubernetes'    
// 		sonarProjectKey = 'shared_services_kubernetes'

		BuildCommand = "mvn clean package -DskipTests -Dspring.profiles.active=${params.environment}"
		BuildJarName = 'admin-service/target/admin-service-1.0.0-SNAPSHOT.jar'
		BuildEnvs = "${params.environment}"

		unitTestCommand = 'mvn test'
	}

    stages {
	    stage('Validate Branch Name') {
            steps {
                script {
                    if (!params.branchName.matches('''^sprint-\\d+$''')) {
                        error("Invalid branchName: '${params.branchName}'. It must start with 'sprint-' followed by numbers only, e.g., sprint-123")
                    }
                }
            }
        }
        
        stage('Checkout Source Code') {
            steps {
				timestamps {
					checkout changelog: false, poll: false, 
					scm: scmGit(branches: [[name: env.branchName]], 
					extensions: [cleanBeforeCheckout(), 
					[$class: 'SparseCheckoutPaths', sparseCheckoutPaths: [[path: "${env.rootFolder}/${env.subFolder}"]]]], 
					userRemoteConfigs: [[credentialsId: 'f7168bec-d1a1-4420-b7ed-683332028405', 
					url: env.repoUrl]])
					
					sh "cp -ar ${env.rootFolder}/${env.subFolder}/. \$WORKSPACE && rm -rf ${env.rootFolder}"
				}
			}
        }

//         stage('SonarQube Analysis') {
// 			when {
// 				expression {
// 					return params.environment == 'dev'
// 				}
// 			}
// 			steps {
// 				timestamps {
// 					ansiColor('xterm') {
// 						sh "export JAVA_HOME=\"/usr/lib/jvm/java-21-openjdk-amd64/\" && \
// 						cd /opt/scripts/ && ./sonarscan_maven.sh \"${env.sonarqGate}\" \"${env.sonarCommand}\" \"${env.sonarProjectName}\" \"${env.sonarProjectKey}\""
// 					}
// 				}
// 			}
// 		}

// 		stage('Unit Testing') {
// 			when {
// 				expression {
// 					env.unitTestStageBool.toBoolean()
// 				}
// 			}
// 			steps {
// 				timestamps {
// 					ansiColor('xterm') {
// 						sh "${env.unitTestCommand}"
// 					}
// 				}
// 			}
// 		}

		stage('Build Artifact') {
        	steps {
        		timestamps {
        			ansiColor('xterm') {
        				sh """
        					export JAVA_HOME="/usr/lib/jvm/java-21-openjdk-amd64/"
        					${env.BuildCommand}
        					export JAVA_HOME="/usr/lib/jvm/java-8-openjdk-amd64/jre/"
        				"""
        				// ADD THIS DEBUG SECTION - CRITICAL!
        				 sh """
        				     echo "========== DEBUGGING JAR FILES =========="
                             echo "Current directory:"
                             pwd
                             echo "Directory structure:"
                             ls -la
                             echo "Target directory contents:"
                             ls -la target/ 2>/dev/null || echo "No target directory found"
                             echo "All JAR files in workspace:"
                             find . -name "*.jar" -type f 2>/dev/null || echo "No JAR files found"
                             echo "All files containing 'admin':"
                             find . -name "*admin*" -type f 2>/dev/null || echo "No admin files found"
                             echo "Maven target directory search:"
                             find . -name "target" -type d 2>/dev/null || echo "No target directories found"
                             echo "=========================================="
                """
                    
               
                    sh """
        				    mkdir -p "$BACKUP_PATH_BUILD/"
        					cp -ar "$WORKSPACE/${env.BuildJarName}" "$BACKUP_PATH_BUILD/"
        					echo "Copied the artifact: $WORKSPACE/${env.BuildJarName} to $BACKUP_PATH_BUILD/"
        				"""
        			}
        		}
        	}
        }




// 		stage('Push to S3') {
// 			steps {
// 				timestamps {
// 					ansiColor('xterm') {
// 						sh '''
// 						cd /opt/scripts
// 						./aws_s3_put_object.sh
// 						'''
// 					}
// 				}
// 			}
// 		}

//         stage('S3 Pull') {
//             steps {
//                 timestamps {
//                     ansiColor('xterm') {
//                         sh """
//                             aws --profile jenkins_s3_push s3 sync s3://\$ARTIFACTS_BACKUP_BUCKET_NAME/artifacts_backup/\$JOB_NAME/\$BUILD_NUMBER/ /common/jenkins/promoted_builds/\$JOB_NAME/\$BUILD_NUMBER/ --quiet
    
//                           if [ ! "\$(ls -A /common/jenkins/promoted_builds/\$JOB_NAME/\$BUILD_NUMBER/)" ]; then
//                               echo 'S3 Fetch Status: Failure'
//                               exit 1
//                           else
//                               echo 'S3 Fetch Status: Success'
//                           fi
//                       """
//                     }
//                 }
//             }
//         }

		stage('Build Image') {
			steps {
				timestamps {
					ansiColor('xterm') {
						script {
							def ecrRepo = "fmg-insuranceapps"
							def ecrAccount = (params.environment == 'qa') ? "702230634984" : "116762271881"
							def awsProfile = (params.environment == 'qa') ? "jenkins_serverless_mgmt_user_stage" : "jenkins_serverless_mgmt_user_dev"

							sh """
							mkdir -p /common/jenkins/promoted_builds/$JOB_NAME/$BUILD_NUMBER/${env.BuildEnvs}
                 
                            cp -ar $WORKSPACE/* /common/jenkins/promoted_builds/$JOB_NAME/$BUILD_NUMBER/${env.BuildEnvs}
                            
                            ls /common/jenkins/promoted_builds/$JOB_NAME/$BUILD_NUMBER/${env.BuildEnvs}
                            


							export DOCKER_BUILDKIT=1
							docker build -f admin-service/Dockerfile --build-arg SPRING_PROFILES_ACTIVE=${params.environment} -t ${params.imageTag} .

							docker tag ${params.imageTag}:latest ${ecrAccount}.dkr.ecr.us-east-1.amazonaws.com/${ecrRepo}:${params.imageTag}
							aws --profile ${awsProfile} ecr get-login-password | docker login --username AWS --password-stdin ${ecrAccount}.dkr.ecr.us-east-1.amazonaws.com
							docker push ${ecrAccount}.dkr.ecr.us-east-1.amazonaws.com/${ecrRepo}:${params.imageTag}

							docker rmi ${ecrAccount}.dkr.ecr.us-east-1.amazonaws.com/${ecrRepo}:${params.imageTag} || true
							docker rmi ${params.imageTag}:latest || true

							echo "Running ECR image cleanup"
							/opt/scripts/schrute_ecr_cleanup.sh "${ecrRepo}" "us-east-1" 2 "${awsProfile}"
							"""
						}
					}
				}
			}
		}
    }
}
from the pipeline.sh i once the image is build and push to ECR then I need to update the imasge tag in helm repo values.yaml

Helm repo URL: https://git-codecommit.us-east-1.amazonaws.com/v1/repos/Phoenix-helm-chart
path: phoenix=mt/
values file: values.yaml

in this values.yaml i need to update only the image tag of admin service.

