deploy_lambdaedge(){

    echo "+--------------------+"
	echo "| Deploy Lambda edge |"
	echo "+--------------------+"

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
}