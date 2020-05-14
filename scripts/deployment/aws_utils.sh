# Check if a aws parameter exist in parameter store or init it
# $1 Paramter Key
# $2 Default Value
# $3 Region
check_aws_parameter_or_init(){

    AWS_PARAMETER_KEY=$1
    AWS_PARAMETER_DEFAULT_VALUE=$2
    AWS_PARAMETER_REGION=$3

    AWS_PARAMETER_VALUE=$(aws ssm get-parameter --name "${AWS_PARAMETER_KEY}" --region "${AWS_PARAMETER_REGION}" | jq -r ".Parameter.Value")

    if [[ -z "$AWS_PARAMETER_VALUE" ]]; then
        result=$(aws ssm put-parameter --name "${AWS_PARAMETER_KEY}" --type "String" --value "${AWS_PARAMETER_DEFAULT_VALUE}" --region "${AWS_PARAMETER_REGION}" --overwrite)
        echo Parameter $AWS_PARAMETER_KEY initialized
    fi
}

# Check Cloudformation stack status
check_stack_status(){

	local stack_request='aws cloudformation describe-stacks --stack-name '$1' --region '$2
	stack_status=$(${stack_request} | jq -r ".Stacks[].StackStatus")

	echo "Stack is in status :${stack_status}"

	if [[ -z "${stack_status}" ]]
	then
		echo "Status is KO and deployment must stop"
		echo "Please check circleci logs. Stack doesnt exists"
		exit 12
	fi

	if [[ ${stack_status} == *"FAILED" ]]
	then
		echo "Status is KO and deployment must stop"
		echo "Please check events in cloudformation logs, fix issue(s), delete the stack and rerun deployment"
		exit 12
	fi

	if [[ ${stack_status} == *"IN_PROGRESS" ]]
	then
		echo "Status is KO and deployment must stop"
		echo "Please check events in cloudformation logs, fix issue(s) and rerun deployment"
		exit 12
	fi

	echo "Status is OK and deployment can continue"
}

# Create AWS Key Pair by awscli
create_aws_key_pair(){

	echo "+---------------------+"
	echo "| Create AWS Key Pair |"
	echo "+---------------------+"

    keypair_name=${TARGET_ENVIRONMENT}-${APPLICATION_NAME}-KeyPair
    existing_keypair=$(aws ec2 describe-key-pairs --region ${REGION} | jq -r ".KeyPairs[] | select((.KeyName | index(\""${keypair_name=}"\"))) | .KeyName")
    
    if [[ -z "${existing_keypair}" ]]; then
        echo "Try to create KeyPair : ${keypair_name}"
        existing_keypair=$(aws ec2 create-key-pair --key-name ${keypair_name} --region ${REGION} | jq -r ".KeyName")
        if [[ -z "${existing_keypair}" ]]; then
            echo "Failed to create Key Pair : ${keypair_name}"
            exit 12
        fi
    fi
    
    echo "The KeyPair ${existing_keypair} is now existing"
}
