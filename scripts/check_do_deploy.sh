#!/bin/bash
set -eu

# Imports
. ./scripts/deployment/aws_utils.sh
. ./scripts/deployment/s3_backup_utils.sh
. ./scripts/deployment/check_update_type.sh

# Init AWS key
create_aws_key_pair
echo "Check if deployment is required on ${TARGET_ENVIRONMENT}."

# Get current deployed image version
get_backup_bucket_value current_bitnami_wp ${S3_BACKUP_CURRENT_FILE} 'bitnamitag' 'NONE'

# Init NEXT_BITNAMI_WP_TAG and WP_UPDATE_TYPE
check_update_type next_bitnami_wp wp_update_type "${current_bitnami_wp}"

echo "Current bitnami version: ${current_bitnami_wp}"
echo "Next bitnami version: ${next_bitnami_wp}"
echo "Update type: ${wp_update_type}"

do_deploy=0

# INFO : This structure could be improve technicaly regrouping conditions but this is important to keep it like this
# It is more readable like this to understand workflow (see workflow adr)
if [ "${wp_update_type}" == "NONE" ] && [ "${PIPELINE_FROM_CRON}" == false ] && [ "${PIPELINE_FROM_API}" == false ]; then
    # No version update but trigger manually by commit 
    do_deploy=1
elif [ "${wp_update_type}" == "MINOR" ]; then
    # Minor update always deployed
    do_deploy=1
elif [ "${wp_update_type}" == "MAJOR" ]; then
    # Major update deployed on all environements execept release
    if [ "${ENVIRONMENT_TYPE}" != "release" ]; then
        do_deploy=1
    elif [ "${PIPELINE_FROM_API}" == true ] && [ "${PIPELINE_FORCE_RELEASE}" == true ]; then
        # Major update deployed on release only from api with force-release parameter
        do_deploy=1
    fi
fi

if [ "${do_deploy}" = "1" ]; then
    echo "Deployment required"
    echo ${wp_update_type} > .do-deploy
    echo ${next_bitnami_wp} > .next-bitnami-tag
else
    echo "No deployment required"
fi