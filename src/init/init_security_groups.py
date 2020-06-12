import hashlib
import json
from urllib.request import urlopen

import boto3

REGION_NAME = 'eu-central-1'
# Name of the service, as seen in the ip-groups.json file, to extract information for
SERVICE = "CLOUDFRONT"
# Ports your application uses that need inbound permissions from the service for
INGRESS_PORTS = {'Https': 443}
# Tags which identify the security groups you want to update
SECURITY_GROUP_TAG_FOR_GLOBAL_HTTPS_1 = {'Name': 'cloudfront_g_1', 'AutoUpdate': 'true', 'Protocol': 'https'}
SECURITY_GROUP_TAG_FOR_REGION_HTTPS_1 = {'Name': 'cloudfront_r_1', 'AutoUpdate': 'true', 'Protocol': 'https'}
SECURITY_GROUP_TAG_FOR_GLOBAL_HTTPS_2 = {'Name': 'cloudfront_g_2', 'AutoUpdate': 'true', 'Protocol': 'https'}
SECURITY_GROUP_TAG_FOR_REGION_HTTPS_2 = {'Name': 'cloudfront_r_2', 'AutoUpdate': 'true', 'Protocol': 'https'}

def lambda_init_handler(event, context):


    response = urlopen(event['url'])
    ip_json = response.read()
    # Load the ip ranges from the url
    ip_ranges = json.loads(ip_json)

    # extract the service ranges
    global_cf_ranges = get_ranges_for_service(ip_ranges, SERVICE, "GLOBAL")
    region_cf_ranges = get_ranges_for_service(ip_ranges, SERVICE, "REGION")

    # deviding into to subranges to avoid over reaching security group limits (canbe inhanced with an arbitrary number of ranges)
    global_ranges_1 = global_cf_ranges[:round(len(global_cf_ranges) / 2)]
    global_ranges_2 = global_cf_ranges[round(len(global_cf_ranges) / 2):]
    region_ranges_1 = region_cf_ranges[:round(len(region_cf_ranges) / 2)]
    region_ranges_2 = region_cf_ranges[round(len(region_cf_ranges) / 2):]

    ip_ranges = {"GLOBAL_1": global_ranges_1, "GLOBAL_2": global_ranges_2, "REGION_1": region_ranges_1, "REGION_2": region_ranges_2}

    # update the security groups
    result = update_security_groups(ip_ranges)

    return result


def get_ranges_for_service(ranges, service, subset):
    service_ranges = list()
    for prefix in ranges['prefixes']:
        if prefix['service'] == service and ((subset == prefix['region'] and subset == "GLOBAL") or (
                subset != 'GLOBAL' and prefix['region'] != 'GLOBAL')):
            service_ranges.append(prefix['ip_prefix'])
    
    return service_ranges


def update_security_groups(new_ranges):
    client = boto3.client('ec2', region_name=REGION_NAME)

    global_https_group_1 = get_security_groups_for_update(client, SECURITY_GROUP_TAG_FOR_GLOBAL_HTTPS_1)
    region_https_group_1 = get_security_groups_for_update(client, SECURITY_GROUP_TAG_FOR_REGION_HTTPS_1)
    global_https_group_2 = get_security_groups_for_update(client, SECURITY_GROUP_TAG_FOR_GLOBAL_HTTPS_2)
    region_https_group_2 = get_security_groups_for_update(client, SECURITY_GROUP_TAG_FOR_REGION_HTTPS_2)

    result = list()
    global_https_updated = 0
    region_https_updated = 0

    for group in global_https_group_1:
        if update_security_group(client, group, new_ranges["GLOBAL_1"], INGRESS_PORTS['Https']):
            global_https_updated += 1
            result.append('Updated ' + group['GroupId'])
    for group in global_https_group_2:
        if update_security_group(client, group, new_ranges["GLOBAL_2"], INGRESS_PORTS['Https']):
            global_https_updated += 1
            result.append('Updated ' + group['GroupId'])
    for group in region_https_group_1:
        if update_security_group(client, group, new_ranges["REGION_1"], INGRESS_PORTS['Https']):
            region_https_updated += 1
            result.append('Updated ' + group['GroupId'])
    for group in region_https_group_2:
        if update_security_group(client, group, new_ranges["REGION_2"], INGRESS_PORTS['Https']):
            region_https_updated += 1
            result.append('Updated ' + group['GroupId'])

    result.append('Updated ' + str(global_https_updated) + ' of ' + str(
        len(global_https_group_1)) + ' CloudFront_g_1 HttpsSecurityGroups')
    result.append('Updated ' + str(region_https_updated) + ' of ' + str(
        len(region_https_group_1)) + ' CloudFront_r_1 HttpsSecurityGroups')
    result.append('Updated ' + str(global_https_updated) + ' of ' + str(
        len(global_https_group_1)) + ' CloudFront_g_2 HttpsSecurityGroups')
    result.append('Updated ' + str(region_https_updated) + ' of ' + str(
        len(region_https_group_1)) + ' CloudFront_r_2 HttpsSecurityGroups')

    return result


def update_security_group(client, group, new_ranges, port):
    added = 0
    removed = 0

    if len(group['IpPermissions']) > 0:
        for permission in group['IpPermissions']:
            if permission['FromPort'] <= port <= permission['ToPort']:
                old_prefixes = list()
                to_revoke = list()
                to_add = list()
                for range in permission['IpRanges']:
                    cidr = range['CidrIp']
                    old_prefixes.append(cidr)
                    if new_ranges.count(cidr) == 0:
                        to_revoke.append(range)
                        print(group['GroupId'] + ": Revoking " + cidr + ":" + str(permission['ToPort']))

                for range in new_ranges:
                    if old_prefixes.count(range) == 0:
                        to_add.append({'CidrIp': range})
                        print(group['GroupId'] + ": Adding " + range + ":" + str(permission['ToPort']))

                removed += revoke_permissions(client, group, permission, to_revoke)
                added += add_permissions(client, group, permission, to_add)
    else:
        to_add = list()
        for range in new_ranges:
            to_add.append({'CidrIp': range})
            print(group['GroupId'] + ": Adding " + range + ":" + str(port))
        permission = {'ToPort': port, 'FromPort': port, 'IpProtocol': 'tcp'}
        added += add_permissions(client, group, permission, to_add)

    print(group['GroupId'] + ": Added " + str(added) + ", Revoked " + str(removed))
    return added > 0 or removed > 0


def revoke_permissions(client, group, permission, to_revoke):
    if len(to_revoke) > 0:
        revoke_params = {
            'ToPort': permission['ToPort'],
            'FromPort': permission['FromPort'],
            'IpRanges': to_revoke,
            'IpProtocol': permission['IpProtocol']
        }

        client.revoke_security_group_ingress(GroupId=group['GroupId'], IpPermissions=[revoke_params])

    return len(to_revoke)


def add_permissions(client, group, permission, to_add):
    if len(to_add) > 0:
        add_params = {
            'ToPort': permission['ToPort'],
            'FromPort': permission['FromPort'],
            'IpRanges': to_add,
            'IpProtocol': permission['IpProtocol']
        }

        client.authorize_security_group_ingress(GroupId=group['GroupId'], IpPermissions=[add_params])

    return len(to_add)


def get_security_groups_for_update(client, security_group_tag):
    filters = list()
    for key, value in security_group_tag.items():
        filters.extend(
            [
                {'Name': "tag-key", 'Values': [key]},
                {'Name': "tag-value", 'Values': [value]}
            ]
        )

    response = client.describe_security_groups(Filters=filters)

    return response['SecurityGroups']
