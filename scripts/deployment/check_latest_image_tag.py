import argparse
import os
import requests
import re
import sys

from distutils.version import LooseVersion


def perform_get_auth_if_needed(get_request):
    resp = requests.get(get_request)
    if not 401 <= resp.status_code <= 403:
        return resp
    else:
        # unauthorized : get token first
        auth_headers_array = resp.headers.get('www-authenticate').split(',')
        auth_dict = {(pair.split('=')[0]).strip(): (pair.split('=')[1]).replace('"', '').strip()
                     for pair in auth_headers_array}
        auth_url = auth_dict.pop('Bearer realm')
        auth_resp = requests.get(auth_url, auth_dict)
        if not auth_resp.status_code == 200:
            raise Exception('Authentication api failed: %s' % auth_resp)
        token = auth_resp.json().get('token')
        auth_header = {'Authorization': 'Bearer ' + token}
        return requests.get(get_request, headers=auth_header)


def fetch_tags_from_registry(image_name):
    registry_url = os.environ.get('DOCKER_REGISTRY_URL', '')
    if not registry_url:
        raise Exception(
            'DOCKER_REGISTRY_URL environment variable is not defined')
    registry_response = None
    retries = 0
    while registry_response is None and retries < 3:
        try:
            registry_response = perform_get_auth_if_needed(
                'https://%s/v2/%s/tags/list' % (registry_url, image_name))
        except requests.exceptions.ChunkedEncodingError:
            # retry
            retries += 1
    if registry_response is None:
        raise Exception('Cannot get a valid response from docker registry')
    if not registry_response.status_code == 200:
        raise Exception('fetch_tags_from_registry failed: %s' %
                        registry_response)
    tags_list = registry_response.json().get('tags')
    return tags_list


def get_latest_version_from_tags_list(tags):
    version_pattern = re.compile(r'^(\d+\.\d+\.\d+)\-debian\-10\-r\d+$')
    # First, filter to keep tags matching the pattern
    filtered_tags = [t for t in tags if version_pattern.match(t)]
    if filtered_tags:
        # Order to get highest version number first
        latest = sorted(filtered_tags, key=lambda x: LooseVersion(
            x), reverse=False).pop()
        m = version_pattern.match(latest)
        wpversion = m.group(1)
        return latest.strip(), wpversion.strip()
    raise Exception('No version tag found')


def get_latest_image_tag():
    return get_latest_version_from_tags_list(fetch_tags_from_registry('bitnami/wordpress'))


if __name__ == "__main__":
    current = sys.argv[1].strip()
    tag, version = get_latest_image_tag()
    print(tag)
    if current == tag:
        print('NONE')
    elif current.startswith(version, 0):
        print('MINOR')
    else:
        print('MAJOR')
