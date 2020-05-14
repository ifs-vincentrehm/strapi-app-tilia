#!/bin/bash
set -eu

# Imports
. ./scripts/deployment/aws_utils.sh
. ./scripts/deployment/s3_backup_utils.sh
. ./scripts/deployment/backup.sh

# Backup DB
get_rds_identifier instance_rds
take_db_snapshot rds_snapshot "${instance_rds}"

# Backup EFS
get_efs_arn fs_id
take_efs_snapshot fs_recoverypoint "${fs_id}"

# Retrieve image uri
image_uri=''
get_running_image_uri image_uri

get_backup_bucket_value current_bitnami_tag ${S3_BACKUP_CURRENT_FILE} 'bitnamitag' 'UNKNOWN'
get_backup_bucket_value current_image_tag ${S3_BACKUP_CURRENT_FILE} 'imagetag' 'UNKNOWN'
get_backup_bucket_value current_deploy_time ${S3_BACKUP_CURRENT_FILE} 'deploytime' 'UNKNOWN'

# Compile these identifiers in backup file
store_backup_infos "${rds_snapshot}" "${fs_recoverypoint}" "${image_uri}" "${current_bitnami_tag}" "${current_image_tag}" "${current_deploy_time}"
