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

echo "+--------------+"
echo "| Call GET Api |"
echo "+--------------+"
echo ${PLUGIN_API_URL}
get_result=$(wget -qO- "${apiArgs[@]}" ${PLUGIN_API_URL}/addons)
echo "$get_result"

# Parse result
plugins_to_update=($( echo $get_result | jq -r '.plugins_to_update[]')) 
plugins_to_install=($( echo $get_result | jq -r '.plugins_to_install[]')) 
themes_to_update=($( echo $get_result | jq -r '.themes_to_update[]')) 
themes_to_install=($( echo $get_result | jq -r '.themes_to_install[]')) 

nb_plugins_to_update=${#plugins_to_update[@]}
nb_plugins_to_install=${#plugins_to_install[@]}
nb_themes_to_update=${#themes_to_update[@]}
nb_themes_to_install=${#themes_to_install[@]}

all_addons=("${plugins_to_update[@]}" "${plugins_to_install[@]}" "${themes_to_update[@]}" "${themes_to_install[@]}")
nb_all_addons=${#all_addons[@]}

echo "+---------------------+"
echo "| Write analysis file |"
echo "+---------------------+"

echo "Result ($nb_all_addons):" > $PLUGIN_ADDONS_ANALYSIS_FILE
echo "" >> $PLUGIN_ADDONS_ANALYSIS_FILE
echo "*** ${nb_plugins_to_update} plugins to update ***" >> $PLUGIN_ADDONS_ANALYSIS_FILE
for ELEMENT in ${plugins_to_update[@]}
do
    echo $ELEMENT >> $PLUGIN_ADDONS_ANALYSIS_FILE
done
echo "" >> $PLUGIN_ADDONS_ANALYSIS_FILE
echo "*** ${nb_plugins_to_install} plugins to install ***" >> $PLUGIN_ADDONS_ANALYSIS_FILE
for ELEMENT in ${plugins_to_install[@]}
do
    echo $ELEMENT >> $PLUGIN_ADDONS_ANALYSIS_FILE
done
echo "" >> $PLUGIN_ADDONS_ANALYSIS_FILE
echo "*** ${nb_themes_to_update} themes to update ***" >> $PLUGIN_ADDONS_ANALYSIS_FILE
for ELEMENT in ${themes_to_update[@]}
do
    echo $ELEMENT >> $PLUGIN_ADDONS_ANALYSIS_FILE
done
echo "" >> $PLUGIN_ADDONS_ANALYSIS_FILE
echo "*** ${nb_themes_to_install} themes to install ***" >> $PLUGIN_ADDONS_ANALYSIS_FILE
for ELEMENT in ${themes_to_install[@]}
do
    echo $ELEMENT >> $PLUGIN_ADDONS_ANALYSIS_FILE
done

echo "File $PLUGIN_ADDONS_ANALYSIS_FILE created"


if [ "${PIPELINE_FROM_API}" == true ] && [ "${PIPELINE_FORCE_ADDONS}" == true ]; then
    force_install_addons=true
else
    force_install_addons=false
fi


if [ ${nb_all_addons} == 0 ]; then

    echo "No addons to update or install"

elif [ "${ENVIRONMENT_TYPE}" != "release" ] || [ "${force_install_addons}" == true ]; then
    
    echo "+---------------+"
    echo "| Call POST Api |"
    echo "+---------------+"

    echo "[" > $PLUGIN_ADDONS_EXECUTION_FILE

    for addon in ${all_addons[@]}
    do
        echo "| Update/Install $addon"
        post_result=$(wget -qO- --method POST "${apiArgs[@]}" ${PLUGIN_API_URL}/addon?addon-name=$addon)
        echo "$post_result"
        echo "$post_result," >> $PLUGIN_ADDONS_EXECUTION_FILE
    done

    echo "]" >> $PLUGIN_ADDONS_EXECUTION_FILE

fi
