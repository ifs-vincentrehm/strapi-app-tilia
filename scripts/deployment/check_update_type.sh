#########################################################
## Function check_update_type
##
## Compares current image version with latest tags on the 
## Docker registry, then compute the update type.
##
## args:
## $1 : output: next tag
## $2 : output: update type
## $3 : input: current version
#########################################################
check_update_type(){

    echo "+-------------------+"
	echo "| Check update type |"
	echo "+-------------------+"

    currentVersion="$3"

    mapfile -t array < <(python scripts/deployment/check_latest_image_tag.py ${currentVersion})

    eval "$1=${array[0]}"
    # NONE, MINOR (bitnami) or MAJOR (wordpress)
    eval "$2=${array[1]}"
}