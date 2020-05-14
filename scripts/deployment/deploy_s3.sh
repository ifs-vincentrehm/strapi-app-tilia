deploy_s3(){

    echo "+-------------------+"
	echo "| Deploy S3 buckets |"
	echo "+-------------------+"

    aws cloudformation deploy \
        --template-file cloudformation/s3.yml \
        --stack-name ${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-s3 \
        --parameter-overrides \
            Environment=${TARGET_ENVIRONMENT} \
            Application=${APPLICATION_NAME} \
            PreviousBackupsDeletedAfterDays=${PREVIOUS_BACKUPS_DELETED_AFTER_DAYS} \
        --tags \
            Project=${PROJECT_NAME} \
            EnvironmentId=${TARGET_ENVIRONMENT} \
            EnvironmentType=${ENVIRONMENT_TYPE} \
            ApplicationName=${APPLICATION_NAME} \
        --capabilities CAPABILITY_IAM \
        --region ${REGION} \
        --no-fail-on-empty-changeset

    check_stack_status ${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-s3 ${REGION}

    cp -p src/ecs-lifecycle-hook/"${LIFECYCLE_LAUNCH_FUNCTION}.py" function.py
    zip "${LIFECYCLE_LAUNCH_FUNCTION}.zip" function.py

    cp -p src/ecs-lifecycle-hook/"${LIFECYCLE_TERMINATE_FUNCTION}.py" function.py
    zip "${LIFECYCLE_TERMINATE_FUNCTION}.zip" function.py

    aws s3 cp "${LIFECYCLE_LAUNCH_FUNCTION}.zip" s3://${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-${ARTEFACTBUCKET}/
    aws s3 cp "${LIFECYCLE_TERMINATE_FUNCTION}.zip" s3://${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-${ARTEFACTBUCKET}/

}