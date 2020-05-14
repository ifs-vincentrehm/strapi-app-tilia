#!/bin/bash

#########################################################
## Function store_current_tags
##
## repoName: name of ECR registry of the deployed image
## imageTag: deployed image tag
## bitnamiTag: tag of the base bitnami image imageTag is built on
## bucketName: name of s3 bucket where info are stored
##
#########################################################
# EXAMPLE USAGE:
# store_current_tags ${REPO_ECR_NAME} ${IMAGE_TAG} ${BITNAMI_WP_TAG} ${BACKUP_BUCKET}
#########################################################
store_current_tags() 
{
    imageTag="$1"
    bitnamiTag="$2"

    storedImage=$(aws ecr describe-images --repository-name ${APP_ECR} --image-ids imageTag=${imageTag} --output json   | jq . --raw-output )
    echo $storedImage

    if [ -z "${storedImage}" ]; then
        echo "ERROR: imageTag ${imageTag} not found in registry ${APP_ECR}"
        exit 1
    fi

    deploy_time=`date +%Y-%m-%d-%H:%M:%S`
    jsonString=$( jq -n \
                    --arg dt "$deploy_time" \
                    --arg it "$imageTag" \
                    --arg bt "$bitnamiTag" \
                    '{deploytime: $dt, imagetag: $it, bitnamitag: $bt}' )
    echo $jsonString > ${S3_BACKUP_CURRENT_FILE}

    aws s3 cp ${S3_BACKUP_CURRENT_FILE} s3://${BACKUP_BUCKET}/${S3_BACKUP_CURRENT_FILE}
}

#########################################################
## Function get_backup_value
## output $1
## bucketFile $2: name of the file in the bucket
## valueToRead $3: name of the value in the file
## defaultValue $4: default value
##
#########################################################
get_backup_bucket_value() 
{
    bucketFile="$2"
    valueToRead="$3"
    defaultValue="${4:-}"

    if [ ! -f "$bucketFile" ]; then
        
        aws s3 ls s3://${BACKUP_BUCKET}/${bucketFile}
        
        if [[ $? -ne 0 ]]; then
            echo "No backup file found"
        else
            aws s3 cp s3://${BACKUP_BUCKET}/${bucketFile} ${bucketFile} 
        fi
    fi

    if [ -f "$bucketFile" ]; then
        result=$(jq -r ".${valueToRead}" ${bucketFile} --raw-output)
    else
        result=${defaultValue}
    fi

    eval "$1=$result"
}


#########################################################
## Function store_backup_infos
##
## $1: rdsSnapshot
## $2: fsRecoverypoint
## $3: imageUri
## $4: bitnamiTag
## $5: imageTag
## $6: initialDeployTime
## $7: bucketName
## $8: bucketFile
#########################################################
store_backup_infos()
{
    rdsSnapshot="$1"
    fsRecoverypoint="$2"
    imageUri="$3"
    bitnamiTag="$4"
    imageTag="$5"
    initialDeployTime="$6"
    
    backup_time=`date +%Y-%m-%d-%H:%M:%S`
    jsonString=$( jq -n \
                    --arg dt "$backup_time" \
                    --arg rs "$rdsSnapshot" \
                    --arg fr "$fsRecoverypoint" \
                    --arg iu "$imageUri" \
                    --arg bt "$bitnamiTag" \
                    --arg it "$imageTag" \
                    --arg idt "$initialDeployTime" \
                    '{backuptime: $dt, rds_snapshot: $rs, efs_recoverypoint: $fr, ecr_image: $iu, bitnami_tag: $bt, image_tag: $it, initial_deploy_time: $idt}' )
    echo $jsonString > ${S3_BACKUP_BACKUP_FILE}

    aws s3 cp ${S3_BACKUP_BACKUP_FILE} s3://${BACKUP_BUCKET}/${S3_BACKUP_BACKUP_FILE}
}

