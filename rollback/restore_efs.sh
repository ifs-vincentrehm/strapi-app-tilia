#!/bin/sh

set -eu

DIRECTORY='/bitnami/wordpress'

cd ${DIRECTORY}
latest_restore_dir=$(ls -td ${DIRECTORY}/aws-backup-restore*/ 2> /dev/null | head -1)

if [ -z "${latest_restore_dir}" ]; then
    echo "No restore directory found, nothing to do"
    exit 0
fi

echo "Restoring file system from restore directory ${latest_restore_dir}"

# delete current
rm -rf ${DIRECTORY}/wp-content ${DIRECTORY}/wp-config.php

# replace current files with restored files
cp -rfp ${latest_restore_dir}/wp-content ${DIRECTORY}/wp-content
cp -fp ${latest_restore_dir}/wp-config.php ${DIRECTORY}/wp-config.php

chown bitnami:root ${DIRECTORY}/wp-config.php
chown -R bitnami:root ${DIRECTORY}/wp-content

# delete restore dir
rm -rf ${latest_restore_dir}

echo "File system restored"
exit 0