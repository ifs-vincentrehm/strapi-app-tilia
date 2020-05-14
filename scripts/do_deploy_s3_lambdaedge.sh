#!/bin/bash
set -eu

# Imports
. ./scripts/deployment/aws_utils.sh
. ./scripts/deployment/deploy_s3.sh
. ./scripts/deployment/deploy_lambdaedge.sh

# Cloud formation
deploy_s3
deploy_lambdaedge
