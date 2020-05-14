#!/bin/bash
set -eu

# Imports
. ./scripts/deployment/aws_utils.sh
. ./scripts/deployment/s3_backup_utils.sh
. ./scripts/deployment/deploy_main_stack.sh

next_bitnami_wp_tag=$(cat .next-bitnami-tag)
echo "Bitnami image tag to be installed: ${next_bitnami_wp_tag}"

# Deploy main stack
deploy_main_stack image_tag ${next_bitnami_wp_tag} 

# Update current.json file to s3
store_current_tags ${image_tag} \
                   ${next_bitnami_wp_tag}
