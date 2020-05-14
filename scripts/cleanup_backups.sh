#!/bin/bash
set -eu

. ./scripts/deployment/s3_backup_utils.sh
. ./scripts/deployment/backup.sh

# Find DB instance identifier
get_rds_identifier instance_rds

# Find EFS arn
get_efs_arn efs_arn

#Get current image tag
get_backup_bucket_value current_tag "${S3_BACKUP_CURRENT_FILE}" "imagetag"

echo "Deleting expired backups artifacts..."
python scripts/deployment/clean_old_backups.py "${BACKUP_BUCKET}" \
                                              "${S3_BACKUP_BACKUP_FILE}" \
                                              "${instance_rds}" \
                                              "${BACKUPVAULT_NAME}" \
                                              "${efs_arn}" \
                                              "${BACKUP_ARTEFACT_TAG}" \
                                              "${APP_ECR}" \
                                              "${current_tag}"
                                              
echo "Backups cleanup done."