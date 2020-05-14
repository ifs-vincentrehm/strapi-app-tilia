#!/bin/bash


###################################################
## Check Existing Service Linked Role
###################################################
echo "Check if role ${RDS_SERVICELINKEDROLE} exists or not"
EXISTING_ROLE=$(aws iam get-role --role-name ${RDS_SERVICELINKEDROLE})
if [[ -z "${EXISTING_ROLE}" ]]; then
    echo "Role ${RDS_SERVICELINKEDROLE} doesnt exist. Please asks Core Team IT to check why the role doesn't exist and to create it"
    exit 12
fi
###################################################
## Check prerequesite existing stacks
###################################################
PREREQUESITESTACK_LIST=${VPC_STACKNAME}
MISSING_STACK=''

for PREREQUESITESTACK in ${PREREQUESITESTACK_LIST}
do
    echo "Treating stack : ${PREREQUESITESTACK}"
    EXISTING_STACK=$(aws cloudformation describe-stacks --region ${REGION} | jq -r ".Stacks[] | select((.StackName|index(\""${PREREQUESITESTACK}"\"))) | .StackName")
    if [[ -z "${EXISTING_STACK}" ]]; then
        echo "Stack doesnt exist : ${PREREQUESITESTACK}"
        MISSING_STACK=${PREREQUESITESTACK}:${MISSING_STACK}
    fi
done

echo "Prerequestite stacks : ${PREREQUESITESTACK_LIST}"
echo "Missing prerequesite stacks : ${MISSING_STACK}"
if [[ -n "${MISSING_STACK}" ]]; then
    echo "Exit pipeline as following stacks are missing : ${MISSING_STACK}"
    exit 12
fi



