#!/bin/bash
set -eu

# Imports
. ./scripts/deployment/aws_utils.sh
. ./scripts/deployment/wp_plugin_utils.sh

# Create artefact folder
mkdir $PLUGIN_ARTEFACT_FOLDER;

# Prepare API call
PLUGIN_API_URL="https://${WP_ENDPOINT}${PLUGIN_END_POINT}"

# Get credentials
get_lambda_edge_header lambdaHeader
get_wp_plugin_header wpApiHeader
declare -a apiArgs=('--header' "${lambdaHeader}" '--header' "${wpApiHeader}")

echo "+---------------------+"
echo "| Call Heathcheck Api |"
echo "+---------------------+"
echo ${PLUGIN_API_URL}
get_result=$(wget -qO- "${apiArgs[@]}" ${PLUGIN_API_URL}/healthcheck)
echo "$get_result"
echo "$get_result" > $PLUGIN_HEALTHCHECK_EXECUTION_FILE

api_response=($( echo $get_result | jq -r '.api_response'))
multisite=($( echo $get_result | jq -r '.allowMultiSite'))

if [ ${api_response} != 'OK' ]; then
    exit 1;
fi

if [ ${multisite} != '1' ]; then
    exit 1;
fi