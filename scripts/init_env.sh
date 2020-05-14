#!/bin/bash
set -eux

export CONF=$1
if [ -z "${CONF}" ]
then
        echo "Please fill the conf file to use"
        echo "Ex: bash scripts/init_env.sh develop"
        exit 1
fi

if [ ! -f "config/${CONF}.ini" ]
then
        echo "Conf file ${CONF} doesn't exists"
        exit 1
fi


export TARGET_ENVIRONMENT=$(echo $CIRCLE_BRANCH | cut -d'/' -f 1)
echo "export APPLICATION_NAME=${CIRCLE_PROJECT_REPONAME}" >> $BASH_ENV

source config/common.ini
source config/${CONF}.ini

export TARGET_ENVIRONMENT=${CONF}

echo "TARGET ENV : $TARGET_ENVIRONMENT"

echo "export TARGET_ENVIRONMENT=$TARGET_ENVIRONMENT" >> $BASH_ENV
echo "$(cat config/common.ini)" >> $BASH_ENV
echo "$(cat config/${CONF}.ini)" >> $BASH_ENV

echo "export BACKUP_BUCKET=${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-${BACKUPSBUCKET}" >> $BASH_ENV
echo "export APP_ECR=${PREFIX_REPO_ECR}/${TARGET_ENVIRONMENT}-${APPLICATION_NAME}" >> $BASH_ENV
echo "export ROLLBACK_ECR=${PREFIX_REPO_ECR}/${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-rollback" >> $BASH_ENV


