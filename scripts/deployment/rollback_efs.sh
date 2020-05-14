restore_efs_recoverypoint(){

    echo "+---------------------------+"
	echo "| Restore EFS recoverypoint |"
	echo "+---------------------------+"

    local efsrp_arn=$1
    local backupVault=$2
    local backupRoleName=$3

    metadata=$( \
        aws backup get-recovery-point-restore-metadata --backup-vault-name ${backupVault} --recovery-point-arn ${efsrp_arn} --output json \
        | jq  -r '.RestoreMetadata' --raw-output \
    )

    # | jq --arg items '[/wp-config.php, /wp-content]' '. + {ItemsToRestore: $items, newFileSystem: "false"}')
    metadata=$(echo ${metadata} | jq -r '. + {newFileSystem: "false"}' --raw-output )

    roleForBackupArn=$(aws iam get-role --role-name ${backupRoleName} | jq -r ".Role.Arn")

    job=$(aws backup start-restore-job --recovery-point-arn "${efsrp_arn}" \
                                 --metadata "${metadata}" \
                                 --iam-role-arn "${roleForBackupArn}" \
                                 --output json \
                | jq -r '.RestoreJobId' --raw-output)
    
    echo "EFS recoverypoint restore start"
    jobstatus="RUNNING"
    while [[ "${jobstatus}" =~ ^(PENDING|RUNNING)$ ]]; do
        jobinfo=$(aws backup describe-restore-job --restore-job-id ${job} --output json)
        jobstatus=$(echo ${jobinfo} | jq -r '.Status' --raw-output)
        jobpercent=$(echo ${jobinfo} | jq -r '.PercentDone' --raw-output)
        if [[ -z ${jobpercent} ]]; then
            echo "Restoring: ${jobpercent}% done..."
        else
            echo "Restoring ; current status: ${jobstatus} ..."
        fi
        sleep 15s
    done

    if [[ "${jobstatus}" != "COMPLETED" ]]; then
        echo "Bad status for restore job: ${jobstatus}"
        exit 1
    fi
}

apply_restored_files() {
    echo "+----------------------+"
	echo "| Apply restored files |"
	echo "+----------------------+"

    local targetEnvironment=$1
    local applicationName=$2

    family=${targetEnvironment}-${applicationName}-rollback

    # Retrieve task definition ARN
    taskdef=$(aws ecs list-task-definitions --family-prefix ${family} --output json | jq -r '.taskDefinitionArns[0]' --raw-output )

    if [[ -z ${taskdef} ]]; then
        echo "No active task definition found for family ${family}"
        exit 1
    fi

    # Retrieve ECS cluster ARN
    cluster=$(aws ecs list-clusters --output json \
                | jq -r ".clusterArns[] | select(index(\""${targetEnvironment}-${applicationName}"\")>=0)" --raw-output \
                | head -1 \
            )
    
    if [[ -z ${cluster} ]]; then
        echo "No ECS cluster found with name starting by ${targetEnvironment}-${applicationName}"
        exit 1
    fi

    echo "Launch rollback docker image"

    task=$(aws ecs run-task \
                    --launch-type EC2 \
                    --region ${REGION} \
                    --cluster ${cluster} \
                    --task-definition ${taskdef} \
                    --count 1 \
                    --output json \
            | jq -r ".tasks[].taskArn" --raw-output)

    if [[ -z ${task} ]]; then
        echo "Task launch failed"
        exit 1
    fi

    echo "Waiting for rollback task to start..."
    aws ecs wait tasks-running --cluster ${cluster} --tasks ${task}
    echo "Rollback task is running..."
    echo "Waiting for rollback task to finish..."
    aws ecs wait tasks-stopped --cluster ${cluster} --tasks ${task}
    echo "Rollback task finished"
}

rollback_efs() {


    echo "* Start EFS rollback *"

    # +---------------------------+
    # | Get EFS recoverypoint arn |
    # +---------------------------+
    get_backup_bucket_value efsrp_arn "${S3_BACKUP_BACKUP_FILE}" 'efs_recoverypoint'
    echo "Recovery point to restore: ${efsrp_arn}"

    # +-----------------------+
    # | Restore recoverypoint |
    # +-----------------------+
    restore_efs_recoverypoint "${efsrp_arn}" "${BACKUPVAULT_NAME}" "${BACKUP_ROLE_NAME}"

    # +----------------------+
    # | Launch rollback task |
    # +----------------------+
    apply_restored_files "${TARGET_ENVIRONMENT}" "${APPLICATION_NAME}"

    echo "* EFS rollback finished *"
}
