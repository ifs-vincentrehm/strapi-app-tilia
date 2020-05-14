rollback_rds(){

    echo "* Start rollback rds *"

    # +---------------------------+
    # | Get curent RDS identifier |
    # +---------------------------+
    get_rds_identifier instance_rds ${TARGET_ENVIRONMENT} ${APPLICATION_NAME}
    echo "RDS instance to be rollbacked: $instance_rds"

    # +-------------------+
    # | Rename curent RDS |
    # +-------------------+
    tmpRdsName="${TARGET_ENVIRONMENT}-rollbacked-${APPLICATION_NAME}"
    rds_data=$(aws rds modify-db-instance --db-instance-identifier "${instance_rds}" --new-db-instance-identifier "$tmpRdsName" --apply-immediately)

    echo "RDS instance ${instance_rds} renaming start"
    sleep 8s
    aws rds wait db-instance-deleted --db-instance-identifier "${instance_rds}"
    echo "RDS instance renaming done from ${instance_rds} to $tmpRdsName"

    # +----------------------+
    # | Get RDS snapshot arn |
    # +----------------------+
    get_backup_bucket_value snapshot_arn ${S3_BACKUP_BACKUP_FILE} 'rds_snapshot'
    echo "Snapshot to restore: ${snapshot_arn}"
    
    # +-------------+
    # | Restore RDS |
    # +-------------+
    rds_inputs=$(echo $rds_data | jq '.DBInstance')

    subnet_group=$( echo $rds_inputs | jq -r '.DBSubnetGroup.DBSubnetGroupName')
    echo "subnet_group: ${subnet_group}"

    security_group=($( echo $rds_inputs | jq -r '.VpcSecurityGroups[].VpcSecurityGroupId'))
    echo "security_groups: ${security_group[@]}"

    multi_az=$( echo $rds_inputs | jq -r '.MultiAZ')
    echo "multi_az: ${multi_az}"
    if [ "${multi_az}" == true ]; then
        multi_az_opt='--multi-az'
    else
        multi_az_opt='--no-multi-az'
    fi
    echo "multi_az_opt: ${multi_az_opt}"
    
    aws rds restore-db-instance-from-db-snapshot \
                --db-instance-identifier "${instance_rds}" \
                --db-snapshot-identifier "${snapshot_arn}" \
                --db-subnet-group-name "${subnet_group}" \
                --vpc-security-group-ids "${security_group[@]}" \
                ${multi_az_opt}

    echo "Snapshot restore started"
    sleep 8s
    aws rds wait db-instance-available --db-instance-identifier "$instance_rds"
    echo "Snapshot restored"

    # +---------------------+
    # | Delete previous RDS |
    # +---------------------+
    aws rds delete-db-instance --db-instance-identifier "$tmpRdsName" --skip-final-snapshot
    echo "Delete previous DB instance"
    sleep 8s
    aws rds wait db-instance-deleted --db-instance-identifier "${tmpRdsName}"
    echo "Previous DB instance deleted"
}

