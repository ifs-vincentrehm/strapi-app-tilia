#!/bin/bash
set -e

deploy () {
    circleci_token="$1"

    read -p 'Caution: this command will deploy the new version to the RELEASE environment. Are you sure ? Press y to proceed ' -n 1 -r proceed
    echo    # (optional) move to a new line
    if [[ $proceed =~ ^[Yy]$ ]]
    then
        curl -X POST \
            --header "Content-Type: application/json" \
            --data '{"branch": "master",
                    "parameters": {
                        "from-api": true,
                        "deploy": true,
                        "rollback": false,
                        "candidate": false,
                        "release": true,
                        "force-release": true,
                        "force-addons": true }
                    }' \
            https://circleci.com/api/v2/project/github/ifs-alpha/wordpress4alpha/pipeline?circle-token=$circleci_token
    else
        echo "Aborted"
    fi
}

display_usage() { 
	echo "usage: set CIRCLECI_TOKEN env var or pass it as arg: deploy_release.sh <CircleCI API personal token>." 
}

if [[  $# == 0 ]] && [[ -z ${CIRCLECI_TOKEN} ]] ; then
    display_usage
    exit 1
elif [[  $# > 1 ]] ; then
    display_usage
    exit 1
elif [[  $# == 1 ]] ; then
    deploy $1
else 
    deploy ${CIRCLECI_TOKEN}
fi