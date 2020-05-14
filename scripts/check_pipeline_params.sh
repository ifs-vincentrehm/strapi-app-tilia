#!/bin/bash
set -eu

echo "PIPELINE_FROM_API: ${PIPELINE_FROM_API}"
echo "PIPELINE_DEPLOY: ${PIPELINE_DEPLOY}"
echo "PIPELINE_ROLLBACK: ${PIPELINE_ROLLBACK}"
echo "PIPELINE_FORCE_RELEASE: ${PIPELINE_FORCE_RELEASE}"
echo "PIPELINE_FORCE_ADDONS: ${PIPELINE_FORCE_ADDONS}"

if [[ $PIPELINE_DEPLOY == $PIPELINE_ROLLBACK ]]; then
    echo 'You have to choose between Deploy or Rollback'
    exit 1
fi

if [ "${PIPELINE_FROM_API}" == false ] && [ "${PIPELINE_FORCE_RELEASE}" == true ]; then
    echo 'Force release should only work from api call'
    exit 1
fi

if [ "${PIPELINE_DEPLOY}" == false ] && [ "${PIPELINE_FORCE_RELEASE}" == true ]; then
    echo 'Force release should only work for deploy'
    exit 1
fi

if [ "${PIPELINE_FROM_API}" == false ] && [ "${PIPELINE_FORCE_ADDONS}" == true ]; then
    echo 'Force addons should only work from api call'
    exit 1
fi

if [ "${PIPELINE_DEPLOY}" == false ] && [ "${PIPELINE_FORCE_ADDONS}" == true ]; then
    echo 'Force addons should only work for deploy'
    exit 1
fi

if [ "${PIPELINE_FROM_API}" == false ] && [ "${PIPELINE_ROLLBACK}" == true ]; then
    echo 'Rollback should only work from api'
    exit 1
fi

