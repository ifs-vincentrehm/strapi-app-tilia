get_lambda_edge_header(){
    
    PS_LAMBDAEDGE_USERNAME_KEY="${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-${SUFFIX_LAMBDAEDGE_USERNAME_KEY}"
    PS_LAMBDAEDGE_USERNAME=$(aws ssm get-parameter --name "${PS_LAMBDAEDGE_USERNAME_KEY}" --region "${REGION}" | jq -r ".Parameter.Value")
    PS_LAMBDAEDGE_PASSWORD_KEY="${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-${SUFFIX_LAMBDAEDGE_PASSWORD_KEY}"
    PS_LAMBDAEDGE_PASSWORD=$(aws ssm get-parameter --name "${PS_LAMBDAEDGE_PASSWORD_KEY}" --region "${REGION}" | jq -r ".Parameter.Value")
    
    lambdaAuthBasicValue=$(echo -n $PS_LAMBDAEDGE_USERNAME:$PS_LAMBDAEDGE_PASSWORD | base64)
    lambdaHeader="Authorization: Basic ${lambdaAuthBasicValue}"
    
    eval "$1='${lambdaHeader}'"
}

get_wp_plugin_header(){
    
    WP_ADMIN_PASSWORD_KEY="${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-${SUFFIX_WP_ADMIN_PASSWORD}"
    WP_ADMIN_PASSWORD=$(aws ssm get-parameter --name "${WP_ADMIN_PASSWORD_KEY}" --region "${REGION}" | jq -r ".Parameter.Value")
    wpAuthBasicValue=$(echo -n admin:$WP_ADMIN_PASSWORD | base64)
    wpApiHeader="BivwakPlugin-Authorization: Basic ${wpAuthBasicValue}"
    
    eval "$1='${wpApiHeader}'"
}