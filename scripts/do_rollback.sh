#!/bin/bash
set -eu

# Imports
. ./scripts/deployment/aws_utils.sh
. ./scripts/deployment/s3_backup_utils.sh
. ./scripts/deployment/backup.sh
. ./scripts/deployment/rollback_efs.sh
. ./scripts/deployment/rollback_rds.sh
. ./scripts/deployment/deploy_main_stack.sh


# Stop service
get_cluster_and_service_identifier cluster_arn cluster_name service_arn service_name

aws application-autoscaling register-scalable-target \
    --service-namespace ecs \
    --scalable-dimension ecs:service:DesiredCount \
    --resource-id "service/${cluster_name}/${service_name}" \
    --min-capacity 0 \
    --max-capacity 0

scaleDownResult=$(aws ecs update-service --cluster ${cluster_arn} --service ${service_arn} --desired-count 0)

echo "Scale down service"
sleep 5s
aws ecs wait services-stable --cluster ${cluster_arn} --services ${service_arn}

rollback_efs
rollback_rds

# Deploy main stack

get_backup_bucket_value rollback_ecr_image ${S3_BACKUP_BACKUP_FILE} 'ecr_image'
get_backup_bucket_value rollback_bitnami_tag ${S3_BACKUP_BACKUP_FILE} 'bitnami_tag'
get_backup_bucket_value rollback_image_tag ${S3_BACKUP_BACKUP_FILE} 'image_tag'

echo "Bitnami image tag to be rollbacked: ${rollback_bitnami_tag}"
echo "From image: ${rollback_image_tag}"

deploy_main_stack image_tag 'NO_NEXT' $rollback_ecr_image

# Update current.json file to s3
store_current_tags ${rollback_image_tag} \
                   ${rollback_bitnami_tag}

# Update backup.json file removing last version
allBackupFileVersion=$(aws s3api list-object-versions --bucket ${BACKUP_BUCKET} --prefix ${S3_BACKUP_BACKUP_FILE})
lastestId=$( echo $allBackupFileVersion | jq -r '.Versions[] | select(.IsLatest==true) | .VersionId')
aws s3api delete-object --bucket ${BACKUP_BUCKET} --key ${S3_BACKUP_BACKUP_FILE} --version-id $lastestId

# Restart service
aws application-autoscaling register-scalable-target \
    --service-namespace ecs \
    --scalable-dimension ecs:service:DesiredCount \
    --resource-id "service/${cluster_name}/${service_name}" \
    --min-capacity ${MIN_INSTANCE_COUNT} \
    --max-capacity ${MAX_INSTANCE_COUNT}

scaleUpResult=$(aws ecs update-service --cluster ${cluster_arn} --service ${service_arn} --desired-count ${DESIRED_INSTANCE_COUNT})

echo "Scale up service"
sleep 5s
aws ecs wait services-stable --cluster ${cluster_arn} --services ${service_arn}

echo "Rollback done !"
