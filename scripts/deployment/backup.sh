#!/bin/bash

get_efs_arn()
{
    fs_id=$(aws efs describe-file-systems \
        | jq -r ".FileSystems[] | select((.Tags[].Key==\"ApplicationName\") and (.Tags[].Value==\"${APPLICATION_NAME}\")) | select((.Tags[].Key==\"EnvironmentId\") and (.Tags[].Value==\"${TARGET_ENVIRONMENT}\"))" \
        | jq -r '.FileSystemId' --raw-output)
    accountId=$(aws sts get-caller-identity --output json | jq .Account --raw-output)
    fsarn="arn:aws:elasticfilesystem:${REGION}:${accountId}:file-system/${fs_id}"

    eval "$1=${fsarn}"
}

get_rds_identifier()
{
    instance_rds=$(aws rds describe-db-instances \
        | jq -r ".DBInstances[] | select((.DBInstanceIdentifier|index(\""${TARGET_ENVIRONMENT}-${APPLICATION_NAME}"\")>=0)) " \
        | jq -r '.DBInstanceIdentifier' --raw-output)
    
    eval "$1=${instance_rds}"
}

get_cluster_and_service_identifier()
{
    cluster_arn=$(aws ecs list-clusters \
        | jq -r ".clusterArns[] | select((index(\""${TARGET_ENVIRONMENT}-${APPLICATION_NAME}"\")>=0)) " --raw-output )

    cluster_name=$(aws ecs describe-clusters --cluster $cluster_arn \
        | jq -r ".clusters[0].clusterName" --raw-output )
    
    service_arn=$(aws ecs list-services --cluster $cluster_arn \
        | jq -r ".serviceArns[] | select((index(\""${TARGET_ENVIRONMENT}-${APPLICATION_NAME}"\")>=0)) " --raw-output )

    service_name=$(aws ecs describe-services --cluster ${cluster_arn} --services ${service_arn} \
        | jq -r ".services[0].serviceName" --raw-output )

    eval "$1=${cluster_arn}"
    eval "$2=${cluster_name}"
    eval "$3=${service_arn}"
    eval "$4=${service_name}"

    echo "cluster_arn=${cluster_arn}"
    echo "cluster_name=${cluster_name}"
    echo "service_arn=${service_arn}"
    echo "service_name=${service_name}"
}


#########################################################
## Function take_efs_snapshot
##
## args:
## $1 output created recovery point 
## $2 : fsIdentifier (name of EFS to backup)
#########################################################
take_efs_snapshot(){

    local fsarn="$2"

    roleForBackupArn=$(aws iam get-role --role-name ${BACKUP_ROLE_NAME} | jq -r ".Role.Arn")

    if [ -z "${accountId}" ]; then
        echo "ERROR: failed to retrieve current account id"
    fi

    if [ -z "${roleForBackupArn}" ]; then
        echo "ERROR: failed to retrieve role with name ${BACKUP_ROLE_NAME}"
    fi

    backup=$(aws backup start-backup-job --backup-vault-name ${BACKUPVAULT_NAME} \
                                         --resource-arn ${fsarn} \
                                         --iam-role-arn ${roleForBackupArn} \
                                         --recovery-point-tags ${BACKUP_ARTEFACT_TAG} )
    
    if [ -z "${backup}" ]; then
        echo "ERROR: failed to create backup for file-system ${fsarn}"
    fi

    out=$(echo ${backup} | jq .RecoveryPointArn --raw-output)
    if [ -z "${out}" ]; then
        eval "$1=NONE"
    else
        eval "$1=$out"
    fi
}

#########################################################
## Function take_db_snapshot
##
## args:
## $1 output created snapshot name
## $2 : instanceName: name of RDS DB instance to snapshot
#########################################################
take_db_snapshot() 
{
    local instanceName="$2"
    snapshotTime=`date +%Y-%m-%d-%H%M%S`
    snapshotName=snpdb-${instanceName}-${snapshotTime}

    snap=$(aws rds create-db-snapshot \
                --db-instance-identifier ${instanceName} \
                --db-snapshot-identifier ${snapshotName} --output json \
                | jq .DBSnapshot
                )

    if [ -z "${snap}" ]; then
        echo "ERROR: failed to create snapshot for ${instanceName}"
    fi

    out=$(echo ${snap} | jq .DBSnapshotArn --raw-output)
    if [ -z "${out}" ]; then
        eval "$1=NONE"
    else
        eval "$1=$out"
        # tag snapshot
        IFS='=' read -r -a array <<< ${BACKUP_ARTEFACT_TAG}
        key=${array[0]}
        val=${array[-1]}
        aws rds add-tags-to-resource --resource-name ${out} --tags Key=${key},Value=${val}
    fi
}

#########################################################
## Function get_running_image_uri
##
## args:
## $1 output deployed image full uri or none if not found
#########################################################
get_running_image_uri() 
{
    local taskdefFamily="${TARGET_ENVIRONMENT}-${APPLICATION_NAME}"

    taskdefArn=$(aws ecs list-task-definitions --family-prefix ${taskdefFamily} --status ACTIVE --output json | jq '.taskDefinitionArns[]' --raw-output)

    if [ -z "${taskdefArn}" ]; then
        echo "ERROR: failed to get taskdefArn for family ${taskdefFamily}"
        out=""
    else
        # echo ${taskdefArn}
        taskdef=$(aws ecs describe-task-definition --task-definition ${taskdefArn} --output json)
        out=$(echo ${taskdef} | jq '.taskDefinition.containerDefinitions[0].image' --raw-output)
    fi
    if [ -z "${out}" ]; then
        eval "$1=NONE"
    else
        eval "$1=$out"
    fi
}
