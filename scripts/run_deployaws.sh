init_ecr_repo(){

    local repo_ecr_name="$3"
    local lfpolicy="${4:-}"

    repo_ecr_uri=$(aws ecr describe-repositories --region ${REGION} --repository-name ${repo_ecr_name} | jq -r .repositories[].repositoryUri)
    if [[ -z "${repo_ecr_uri}" ]]; then
        echo "Repository ECR doesn't exist so we create repository"
        repo_ecr_uri=$(aws ecr create-repository --region ${REGION} --repository-name ${repo_ecr_name} | jq -r .repository.repositoryUri)
    fi
    echo "Repository ECR Name: ${repo_ecr_name}"
    echo "Repository ECR URI: ${repo_ecr_uri}"
    $(aws ecr get-login --no-include-email --region ${REGION})

    if [[ -n "${lfpolicy}" ]]; then
        # set lifecycle policy over repo
        aws ecr put-lifecycle-policy --repository-name ${repo_ecr_name} --lifecycle-policy-text "${lfpolicy}"
    fi

    eval "$1=${repo_ecr_name}"
    eval "$2=${repo_ecr_uri}"
}

build_docker_image(){

    echo "+--------------------+"
	echo "| Build docker image |"
	echo "+--------------------+"

    local next_bitnami_wp_tag="$3"

    init_ecr_repo ecr_name ecr_uri ${APP_ECR}

    formated_date=`date +%Y-%m-%d-%H%M%S`
    docker_image_tag=${formated_date}_${next_bitnami_wp_tag}
    uri_docker_image=${ecr_uri}:${docker_image_tag}
    echo "Docker Image Name ${uri_docker_image}"

    docker build -t ${ecr_name} -t ${uri_docker_image} --build-arg IMAGE_TAG=${next_bitnami_wp_tag} .
    docker push ${uri_docker_image}

    eval "$1=${uri_docker_image}"
    eval "$2=${docker_image_tag}"
}

build_rollback_docker_image(){

    echo "+-----------------------------+"
	echo "| Build rollback docker image |"
	echo "+-----------------------------+"

    init_ecr_repo ecr_name ecr_uri ${ROLLBACK_ECR} "file://scripts/deployment/ecr_rollback_policy.json"
    uri_rollback_docker_image=${ecr_uri}:latest
    docker build -t ${uri_rollback_docker_image} -f rollback/Dockerfile .
    docker push ${uri_rollback_docker_image}

    eval "$1=${uri_rollback_docker_image}"
}

deploy_main_stack(){

    local next_bitnami_wp_tag="$2"
    local rollback_image="${3:-}"

    if [ ! -z "${rollback_image}" ]; then
        echo "Rollback process using ${rollback_image}"
        uri_image=${rollback_image}
    else
        echo "Deploy process using ${next_bitnami_wp_tag}"
        build_docker_image uri_image image_tag "$next_bitnami_wp_tag"
        eval "$1=${image_tag}" 
    fi

    build_rollback_docker_image uri_rollback_image

    echo "+-------------------+"
	echo "| Deploy main stack |"
	echo "+-------------------+"

    # Init parameters
    PS_DB_NAME_KEY="${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-${SUFFIX_DB_NAME_KEY}"
    PS_DB_USERNAME_KEY="${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-${SUFFIX_DB_USERNAME_KEY}"
    PS_DB_USER_PASSWORD_KEY="${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-${SUFFIX_DB_USER_PASSWORD_KEY}"
    WP_ADMIN_EMAIL_KEY="${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-${SUFFIX_WP_ADMIN_EMAIL}"
    WP_ADMIN_PASSWORD_KEY="${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-${SUFFIX_WP_ADMIN_PASSWORD}"

    check_aws_parameter_or_init ${PS_DB_NAME_KEY} $(pwgen -0 -A 10 1) ${REGION}
    check_aws_parameter_or_init ${PS_DB_USERNAME_KEY} $(pwgen -0 -A 10 1) ${REGION}
    check_aws_parameter_or_init ${PS_DB_USER_PASSWORD_KEY} $(pwgen -c -s 30 1) ${REGION}
    check_aws_parameter_or_init ${WP_ADMIN_EMAIL_KEY} $(pwgen -0 -A 10 1) ${REGION}
    check_aws_parameter_or_init ${WP_ADMIN_PASSWORD_KEY} $(pwgen -c -s 30 1) ${REGION}

    # Get deployed lambdaedge Basic Auth and security versions
    LAMBDABASICAUTHVERSION=$(aws cloudformation list-exports --region ${LAMBDAEDGE_REGION} | jq -r ".Exports[] | select((.Name|index(\""${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-${LAMBDAEDGE_STACKNAME}-LambdaBasicAuthVersion"\")>=0))" | jq -r ".Value" )
    LAMBDASECURITYVERSION=$(aws cloudformation list-exports --region ${LAMBDAEDGE_REGION} | jq -r ".Exports[] | select((.Name|index(\""${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-${LAMBDAEDGE_STACKNAME}-LambdaSecurityVersion"\")>=0))" | jq -r ".Value" )

    # Get ARN for KMS key of rds
    aws_service_role_for_rds_arn=$(aws iam get-role --role-name AWSServiceRoleForRDS | jq -r ".Role.Arn")
    us_certificate_arn=$(aws cloudformation list-exports --region ${WORLD_REGION} | jq -r ".Exports[] | select((.Name|index(\""${CERTIFICATE_STACKNAME}-${WORLD_REGION}-CertificateArn"\")))" | jq -r ".Value" )

    # Package and copy to s3 nestedtemplates
    # aws cloudformation package \
    #     --template-file cloudformation/nested/alb.yml \
    #     --output-template-file cloudformation/nested/out-alb.yml \
    #     --s3-bucket ${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-${ARTEFACTBUCKET} \
    #     --s3-prefix ${CIRCLE_BRANCH}/nested/${CIRCLE_SHA1}
    #     --region ${REGION} \

    
    # Deploy nested satck
    echo "Let's deploy the master cloudformation file : ${TARGET_ENVIRONMENT}"
    
    aws cloudformation deploy \
        --template-file cloudformation/master.yml \
        --stack-name ${TARGET_ENVIRONMENT}-${APPLICATION_NAME} \
        --parameter-overrides \
            Environment=${TARGET_ENVIRONMENT} \
            Application=${APPLICATION_NAME} \
            ProjectName=${PROJECT_NAME} \
            EnvironmentType=${ENVIRONMENT_TYPE} \
            VPCStackName=${VPC_STACKNAME} \
            CertificateArn=${CERTIFICATE_STACKNAME} \
            USCertificateArn=${us_certificate_arn} \
            MinClusterSize=${MIN_CLUSTER_SIZE} \
            MaxClusterSize=${MAX_CLUSTER_SIZE} \
            DesiredClusterSize=${DESIRED_CLUSTER_SIZE} \
            Domain=${DOMAIN} \
            ScalableMetricType=${AUTOSCALING_TRIGGER_TYPE} \
            ScalableMetricThreshold=${AUTOSCALING_TRIGGER_THRESHOLD} \
            Cooldown=${AUTOSCALING_TRIGGER_COOLDOWN} \
            InstanceType=${ECS_INSTANCE_TYPE} \
            HostedZoneStackName=${DOMAINNAME_STACKNAME} \
            CertificateStackName=${CERTIFICATE_STACKNAME} \
            DBPort=${DB_PORT} \
            DBType=${DB_TYPE} \
            DBVersion=${DB_VERSION} \
            DBInstanceClass=${DB_INSTANCECLASS} \
            DBAllocatedStorage=${DB_ALLOCATEDSTORAGE} \
            DBName=${PS_DB_NAME_KEY} \
            DBUsername=${PS_DB_USERNAME_KEY} \
            DBUserPassword=${PS_DB_USER_PASSWORD_KEY} \
            DBStorageEncryption=${DB_STORAGEENCRYPTION} \
            DBBackupRetentionPeriod=${DB_BACKUPRETENTIONPERIOD} \
            AWSServiceRoleForRDSArn=${aws_service_role_for_rds_arn} \
            LambdaBasicAuthVersion=${LAMBDABASICAUTHVERSION} \
            LambdaSecurityVersion=${LAMBDASECURITYVERSION} \
            UseBasicAuth=${USE_BASICAUTH} \
            DeploymentS3Bucket=${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-${ARTEFACTBUCKET} \
            LifecycleLaunchFunctionZip="${LIFECYCLE_LAUNCH_FUNCTION}.zip" \
            LifecycleTerminateFunctionZip="${LIFECYCLE_TERMINATE_FUNCTION}.zip" \
            LBPriority=${LB_PRIORITY} \
            ScaleInCooldown=${AUTOSCALING_TRIGGER_SCALEINCOOLDOWN} \
            ScaleOutCooldown=${AUTOSCALING_TRIGGER_SCALEOUTCOOLDOWN} \
            ScaleTriggerType=${AUTOSCALING_TRIGGER_TYPE} \
            ScaleTriggerThreshold=${AUTOSCALING_TRIGGER_THRESHOLD} \
            MinInstanceCount=${MIN_INSTANCE_COUNT} \
            DesiredInstanceCount=${DESIRED_INSTANCE_COUNT} \
            MaxInstanceCount=${MAX_INSTANCE_COUNT} \
            URIDockerImage=${uri_image} \
            URIRollbackDockerImage=${uri_rollback_image} \
            ApplicationRegion=${REGION} \
            LoadbalancerHostedZoneID=${LOADBALANCER_HOSTEDZONEID}\
            AlbDomain=${ALBDOMAIN}\
            WpEndPoint=${WP_ENDPOINT}\
            WpAdminMail=${WP_ADMIN_EMAIL_KEY}\
            WpAdminPwd=${WP_ADMIN_PASSWORD_KEY}\
        --tags \
            Project=${PROJECT_NAME} \
            EnvironmentId=${TARGET_ENVIRONMENT} \
            EnvironmentType=${ENVIRONMENT_TYPE} \
            ApplicationName=${APPLICATION_NAME} \
        --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND CAPABILITY_NAMED_IAM \
        --region ${REGION} \
        --no-fail-on-empty-changeset

    check_stack_status ${TARGET_ENVIRONMENT}-${APPLICATION_NAME} ${REGION}

    # Invoke lamba
    function_name=$(aws cloudformation list-exports --region ${REGION} | jq -r ".Exports[] | select((.Name|index(\""${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-LambdaInitSG"\")))" | jq -r ".Value" )
    aws lambda invoke --function-name $function_name --invocation-type 'Event'  --payload '{"url":"https://ip-ranges.amazonaws.com/ip-ranges.json"}' outputfile.txt

}

#!/bin/bash

###################################################
## Function check stack status
###################################################
check_stack_status() {
  local stack_request='aws cloudformation describe-stacks --stack-name '$1' --region '$2
  stack_status=$(${stack_request} | jq -r ".Stacks[].StackStatus")

  echo "Stack is in status :${stack_status}"

  if [[ -z "${stack_status}" ]]; then
    echo "Status is KO and deployment must stop"
    echo "Please check circleci logs. Stack doesnt exists"
    exit 12
  fi

  if [[ ${stack_status} == *"FAILED" ]]; then
    echo "Status is KO and deployment must stop"
    echo "Please check events in cloudformation logs, fix iss ue(s), delete the stack and rerun deployment"
    exit 12
  fi

  if [[ ${stack_status} == *"ROLLBACK_COMPLETE" ]]; then
    echo "Status is KO and deployment must stop"
    echo "Please check events in cloudformation logs, fix issue(s) and rerun deployment"
    exit 12
  fi

  echo "Status is OK and deployment can continue"
}

###################################################
## Create S3 for swaggers, artefacts and medias
###################################################
TEMPLATE=${S3_STACKNAME}
STACKFULLNAME=${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-${TEMPLATE}
aws cloudformation deploy \
  --template-file cloudformation/${TEMPLATE}.yml \
  --stack-name ${STACKFULLNAME} \
  --parameter-overrides \
  Environment=${TARGET_ENVIRONMENT} \
  Application=${APPLICATION_NAME} \
  VPCStackName=${VPC_STACKNAME} \
  HostedZoneStackName=${DOMAINNAME_STACKNAME} \
  --tags \
  Project=${PROJECT_NAME} \
  EnvironmentId=${TARGET_ENVIRONMENT} \
  EnvironmentType=${ENVIRONMENT_TYPE} \
  ApplicationName=${APPLICATION_NAME} \
  --capabilities CAPABILITY_IAM \
  --region ${REGION} \
  --no-fail-on-empty-changeset

check_stack_status ${STACKFULLNAME} ${REGION}


cp -p src/ecs-lifecycle-hook/"${LIFECYCLE_LAUNCH_FUNCTION}.py" function.py
zip "${LIFECYCLE_LAUNCH_FUNCTION}.zip" function.py

cp -p src/ecs-lifecycle-hook/"${LIFECYCLE_TERMINATE_FUNCTION}.py" function.py
zip "${LIFECYCLE_TERMINATE_FUNCTION}.zip" function.py

aws s3 cp "${LIFECYCLE_LAUNCH_FUNCTION}.zip" s3://${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-${ARTEFACTBUCKET}/
aws s3 cp "${LIFECYCLE_TERMINATE_FUNCTION}.zip" s3://${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-${ARTEFACTBUCKET}/


  export TEMPLATE=${LAMBDAEDGE_STACKNAME}

    # Init parameters
PS_LAMBDAEDGE_USERNAME_KEY="${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-${SUFFIX_LAMBDAEDGE_USERNAME_KEY}"
PS_LAMBDAEDGE_PASSWORD_KEY="${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-${SUFFIX_LAMBDAEDGE_PASSWORD_KEY}"
PS_LAMBDAEDGE_WHITELISTIP_KEY="${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-${SUFFIX_LAMBDAEDGE_WHITELISTIP_KEY}"

check_aws_parameter_or_init ${PS_LAMBDAEDGE_USERNAME_KEY} $(pwgen -0 -A 10 1) ${REGION}
check_aws_parameter_or_init ${PS_LAMBDAEDGE_PASSWORD_KEY} $(pwgen -y -c -s 30 1) ${REGION}
check_aws_parameter_or_init ${PS_LAMBDAEDGE_WHITELISTIP_KEY} ${LAMBDAEDGE_WHITELISTIP} ${REGION}

# Deploy
aws cloudformation package \
    --template-file cloudformation/${TEMPLATE}.yml \
    --output-template-file cloudformation/out-${TEMPLATE}.yml \
    --s3-bucket ${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-${ARTEFACTBUCKET} \
    --s3-prefix ${CIRCLE_BRANCH}/edge/${CIRCLE_SHA1}

aws cloudformation deploy \
    --template-file cloudformation/out-${TEMPLATE}.yml \
    --stack-name ${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-${TEMPLATE} \
    --parameter-overrides \
        ApplicationRegion=${REGION} \
        Environment=${TARGET_ENVIRONMENT} \
        Application=${APPLICATION_NAME} \
        ProjectName=${PROJECT_NAME} \
        EnvironmentType=${ENVIRONMENT_TYPE} \
        UserParameterName=${PS_LAMBDAEDGE_USERNAME_KEY} \
        PasswordParameterName=${PS_LAMBDAEDGE_PASSWORD_KEY} \
        WhiteListIpParameterName=${PS_LAMBDAEDGE_WHITELISTIP_KEY} \
    --tags \
        Project=${PROJECT_NAME} \
        EnvironmentId=${TARGET_ENVIRONMENT} \
        EnvironmentType=${ENVIRONMENT_TYPE} \
        ApplicationName=${APPLICATION_NAME} \
    --capabilities CAPABILITY_NAMED_IAM \
    --region ${LAMBDAEDGE_REGION} \
    --no-fail-on-empty-changeset

check_stack_status ${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-${TEMPLATE} ${LAMBDAEDGE_REGION}

###################################################
## Package maven
###################################################
#mvn clean -q package

###################################################
## Deploy Docker Repository
###################################################
docker build -t ${PREFIX_REPO_ECR}/${APPLICATION_NAME} .

REPO_ECR_NAME=$(aws ecr describe-repositories --region ${REGION} --repository-name ${PREFIX_REPO_ECR}/${APPLICATION_NAME} | jq -r .repositories[].repositoryUri)
if [[ -z "${REPO_ECR_NAME}" ]]; then
  echo "Repository ECR doesn't exist so we create repository"
  REPO_ECR_NAME=$(aws ecr create-repository --region ${REGION} --repository-name ${PREFIX_REPO_ECR}/${APPLICATION_NAME} | jq -r .repository.repositoryUri)
fi
echo "Repository ECR: ${REPO_ECR_NAME}"

echo "export URI_DOCKER_IMAGE=${REPO_ECR_NAME}:${CIRCLE_SHA1}" >>${BASH_ENV}
source ${BASH_ENV}
echo "Docker Image Name ${URI_DOCKER_IMAGE}"

$(aws ecr get-login --no-include-email --region ${REGION})
docker tag ${PREFIX_REPO_ECR}/${APPLICATION_NAME}:latest ${REPO_ECR_NAME}:${CIRCLE_SHA1}
docker push ${URI_DOCKER_IMAGE}

###################################################
## Create Parameter Store Variables by awscli
###################################################
PS_DB_NAME_KEY="${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-${SUFFIX_DB_NAME_KEY}"
PS_DB_USERNAME_KEY="${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-${SUFFIX_DB_USERNAME_KEY}"
PS_DB_USER_PASSWORD_KEY="${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-${SUFFIX_DB_USER_PASSWORD_KEY}"

# On recupere les valeurs des paramters
PS_DB_NAME_VALUE=$(aws ssm get-parameter --name "${PS_DB_NAME_KEY}" --region "${REGION}" | jq -r ".Parameter.Value")
PS_DB_USERNAME_VALUE=$(aws ssm get-parameter --name "${PS_DB_USERNAME_KEY}" --region "${REGION}" | jq -r ".Parameter.Value")
PS_DB_USER_PASSWORD_VALUE=$(aws ssm get-parameter --name "${PS_DB_USER_PASSWORD_KEY}" --region "${REGION}" | jq -r ".Parameter.Value")

# Si les parameters n'existent pas on les cree et on les pousse dans parameter store
if [[ -z "$PS_DB_NAME_VALUE" ]]; then
  # on genere un nom de bdd sans chiffre, sans caracteres speciaux et sans majuscule
  PS_DB_NAME_VALUE=$(pwgen -0 -A 10 1)
  result=$(aws ssm put-parameter --name "${PS_DB_NAME_KEY}" --type "String" --value "${PS_DB_NAME_VALUE}" --region "${REGION}" --overwrite)
fi

if [[ -z "$PS_DB_USERNAME_VALUE" ]]; then
  # on genere un nom de user bdd sans chiffre, sans caracteres speciaux et sans majuscule
  PS_DB_USERNAME_VALUE=$(pwgen -0 -A 10 1)
  result=$(aws ssm put-parameter --name "${PS_DB_USERNAME_KEY}" --type "String" --value "${PS_DB_USERNAME_VALUE}" --region "${REGION}" --overwrite)
fi

if [[ -z "$PS_DB_USER_PASSWORD_VALUE" ]]; then
  # on genere un mot de passe de bdd complexe avec des caracteres speciaux, des nombres et des majuscules
  PS_DB_USER_PASSWORD_VALUE=$(pwgen -y -c -s 30 1)
  result=$(aws ssm put-parameter --name "${PS_DB_USER_PASSWORD_KEY}" --type "String" --value "${PS_DB_USER_PASSWORD_VALUE}" --region "${REGION}" --overwrite)
fi

 # Get deployed lambdaedge Basic Auth and security versions
    LAMBDABASICAUTHVERSION=$(aws cloudformation list-exports --region ${LAMBDAEDGE_REGION} | jq -r ".Exports[] | select((.Name|index(\""${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-${LAMBDAEDGE_STACKNAME}-LambdaBasicAuthVersion"\")>=0))" | jq -r ".Value" )
    LAMBDASECURITYVERSION=$(aws cloudformation list-exports --region ${LAMBDAEDGE_REGION} | jq -r ".Exports[] | select((.Name|index(\""${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-${LAMBDAEDGE_STACKNAME}-LambdaSecurityVersion"\")>=0))" | jq -r ".Value" )

    # Get ARN for KMS key of rds
    aws_service_role_for_rds_arn=$(aws iam get-role --role-name AWSServiceRoleForRDS | jq -r ".Role.Arn")
    us_certificate_arn=$(aws cloudformation list-exports --region ${WORLD_REGION} | jq -r ".Exports[] | select((.Name|index(\""${CERTIFICATE_STACKNAME}-${WORLD_REGION}-CertificateArn"\")))" | jq -r ".Value" )


  # Package and copy to s3 nestedtemplates
    aws cloudformation package \
        --template-file cloudformation/nested/alb.yml \
        --output-template-file cloudformation/nested/out-alb.yml \
        --s3-bucket ${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-${ARTEFACTBUCKET} \
        --s3-prefix ${CIRCLE_BRANCH}/nested/${CIRCLE_SHA1}


aws s3 cp cloudformation/nested/ s3://${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-nestedtemplates/ --recursive

# Deploy nested satck
echo "Let's deploy the master cloudformation file : ${TARGET_ENVIRONMENT}"
    
aws cloudformation deploy \
    --template-file cloudformation/master.yml \
    --stack-name ${TARGET_ENVIRONMENT}-${APPLICATION_NAME} \
    --parameter-overrides \
        Environment=${TARGET_ENVIRONMENT} \
        Application=${APPLICATION_NAME} \
        ProjectName=${PROJECT_NAME} \
        EnvironmentType=${ENVIRONMENT_TYPE} \
        VPCStackName=${VPC_STACKNAME} \
        CertificateArn=${CERTIFICATE_STACKNAME} \
        USCertificateArn=${us_certificate_arn} \
        MinClusterSize=${MIN_CLUSTER_SIZE} \
        MaxClusterSize=${MAX_CLUSTER_SIZE} \
        DesiredClusterSize=${DESIRED_CLUSTER_SIZE} \
        Domain=${DOMAIN} \
        ScalableMetricType=${AUTOSCALING_TRIGGER_TYPE} \
        ScalableMetricThreshold=${AUTOSCALING_TRIGGER_THRESHOLD} \
        Cooldown=${AUTOSCALING_TRIGGER_COOLDOWN} \
        InstanceType=${ECS_INSTANCE_TYPE} \
        HostedZoneStackName=${DOMAINNAME_STACKNAME} \
        CertificateStackName=${CERTIFICATE_STACKNAME} \
        DBPort=${DB_PORT} \
        DBType=${DB_TYPE} \
        DBVersion=${DB_VERSION} \
        DBInstanceClass=${DB_INSTANCECLASS} \
        DBAllocatedStorage=${DB_ALLOCATEDSTORAGE} \
        DBName=${PS_DB_NAME_KEY} \
        DBUsername=${PS_DB_USERNAME_KEY} \
        DBUserPassword=${PS_DB_USER_PASSWORD_KEY} \
        DBStorageEncryption=${DB_STORAGEENCRYPTION} \
        DBBackupRetentionPeriod=${DB_BACKUPRETENTIONPERIOD} \
        AWSServiceRoleForRDSArn=${aws_service_role_for_rds_arn} \
        LambdaBasicAuthVersion=${LAMBDABASICAUTHVERSION} \
        LambdaSecurityVersion=${LAMBDASECURITYVERSION} \
        UseBasicAuth=${USE_BASICAUTH} \
        DeploymentS3Bucket=${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-${ARTEFACTBUCKET} \
        LifecycleLaunchFunctionZip="${LIFECYCLE_LAUNCH_FUNCTION}.zip" \
        LifecycleTerminateFunctionZip="${LIFECYCLE_TERMINATE_FUNCTION}.zip" \
        LBPriority=${LB_PRIORITY} \
        ScaleInCooldown=${AUTOSCALING_TRIGGER_SCALEINCOOLDOWN} \
        ScaleOutCooldown=${AUTOSCALING_TRIGGER_SCALEOUTCOOLDOWN} \
        ScaleTriggerType=${AUTOSCALING_TRIGGER_TYPE} \
        ScaleTriggerThreshold=${AUTOSCALING_TRIGGER_THRESHOLD} \
        MinInstanceCount=${MIN_INSTANCE_COUNT} \
        DesiredInstanceCount=${DESIRED_INSTANCE_COUNT} \
        MaxInstanceCount=${MAX_INSTANCE_COUNT} \
        URIDockerImage=${uri_image} \
        URIRollbackDockerImage=${uri_rollback_image} \
        ApplicationRegion=${REGION} \
        LoadbalancerHostedZoneID=${LOADBALANCER_HOSTEDZONEID}\
        AlbDomain=${ALBDOMAIN}\
    --tags \
        Project=${PROJECT_NAME} \
        EnvironmentId=${TARGET_ENVIRONMENT} \
        EnvironmentType=${ENVIRONMENT_TYPE} \
        ApplicationName=${APPLICATION_NAME} \
    --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND CAPABILITY_NAMED_IAM \
    --region ${REGION} \
    --no-fail-on-empty-changeset

    check_stack_status ${TARGET_ENVIRONMENT}-${APPLICATION_NAME} ${REGION}

    # Invoke lamba
    function_name=$(aws cloudformation list-exports --region ${REGION} | jq -r ".Exports[] | select((.Name|index(\""${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-LambdaInitSG"\")))" | jq -r ".Value" )
    aws lambda invoke --function-name $function_name --invocation-type 'Event'  --payload '{"url":"https://ip-ranges.amazonaws.com/ip-ranges.json"}' outputfile.txt



