#!/bin/bash
set -e

# call the api with the personal api token

rollback () {
    circleci_token="$1"

    read -p 'Caution: this command will rollback to the previous version on the INTEGRATION environment. Are you sure ? Press y to proceed ' -n 1 -r proceed
    echo    # (optional) move to a new line
    if [[ $proceed =~ ^[Yy]$ ]]
    then
        curl -X POST \
            --header "Content-Type: application/json" \
            --data '{"branch": "develop",
                    "parameters": {
                        "from-api": true,
                        "deploy": false,
                        "rollback": true,
                        "candidate": false,
                        "release": false,
                        "force-release": false,
                        "force-addons": false }
                    }' \
            https://circleci.com/api/v2/project/github/ifs-alpha/wordpress4alpha/pipeline?circle-token=$circleci_token
    else
        echo "Aborted"
    fi
}

display_usage() { 
	echo "usage: set CIRCLECI_TOKEN env var or pass it as arg: rollback_release.sh <CircleCI API personal token>." 
}


if [[  $# == 0 ]] && [[ -z ${CIRCLECI_TOKEN} ]] ; then
    display_usage
    exit 1
elif [[  $# > 1 ]] ; then
    display_usage
    exit 1
elif [[  $# == 1 ]] ; then
    rollback $1
else 
    rollback ${CIRCLECI_TOKEN}
fi