import argparse
import boto3
import json


S3 = boto3.client('s3')
RDS = boto3.client('rds')
BACKUP = boto3.client('backup')
ECR = boto3.client('ecr')


def paginate(method, **kwargs):
    """
    Utility method for easy pagination handling
    https://www.reddit.com/r/aws/comments/7p5rhl/using_boto3_think_pagination_adam_johnsons_blog/
    """
    client = method.__self__
    paginator = client.get_paginator(method.__name__)
    for page in paginator.paginate(**kwargs).result_key_iters():
        for result in page:
            yield result


def list_versions(bucket_name, backup_filename, reverse=True):
    versions = [v['VersionId'] for v in paginate(S3.list_object_versions,
                                                 Bucket=bucket_name, Prefix=backup_filename)]
    if reverse:
        versions.reverse()
    return versions


def get_version_content(bucket_name, backup_filename, version):
    obj = S3.get_object(
        Bucket=bucket_name, Key=backup_filename, VersionId=version)
    return json.loads(obj['Body'].read())


def get_references_tokeep(bucket_name, backup_filename, novalue):
    rds_snap_tokeep = set()
    efs_recpoint_tokeep = set()
    ecr_tag_tokeep = set()
    for version in list_versions(bucket_name, backup_filename):
        version_content = get_version_content(
            bucket_name, backup_filename, version)
        rds_snap_tokeep.add(version_content['rds_snapshot'])
        efs_recpoint_tokeep.add(version_content['efs_recoverypoint'])
        # only push the "tag" part of the uri into the set
        ecr_tag_tokeep.add(version_content['ecr_image'].split(':')[-1])
    # remove special id novalue from resulting sets
    rds_snap_tokeep.discard(novalue)
    efs_recpoint_tokeep.discard(novalue)
    ecr_tag_tokeep.discard(novalue)
    return rds_snap_tokeep, efs_recpoint_tokeep, ecr_tag_tokeep


def list_db_snapshots(db_identifier):
    snaps = {snap['DBSnapshotArn'] for snap in paginate(
        RDS.describe_db_snapshots, DBInstanceIdentifier=db_identifier, SnapshotType='manual')}
    return snaps


def delete_snapshots(snapshot_arns, tag_key, tag_value):
    for snap in snapshot_arns:
        # ensure the snapshot has the backup tag, to avoid deleting snapshots not belonging to the the backup process
        if tag_value == {item.get('Key'): item.get('Value') for item in RDS.list_tags_for_resource(ResourceName=snap)['TagList']}.get(tag_key, None):
            snapid = snap.split(':')[-1]
            RDS.delete_db_snapshot(DBSnapshotIdentifier=snapid)
            print('Snapshot %s deleted' % snap)
        else:
            print('Skipping snapshot %s because it does not have the tag %s=%s' % (
                snap, tag_key, tag_value))


def list_efs_recoverypoints(backup_vaultname, efs_arn):
    rps = {rp['RecoveryPointArn'] for rp in BACKUP.list_recovery_points_by_backup_vault(
        BackupVaultName=backup_vaultname, ByResourceType="EFS")['RecoveryPoints'] if rp['ResourceArn'] == efs_arn}
    return rps


def delete_recoverypoints(rp_arn, vaultname, tag_key, tag_value):
    for rp in rp_arn:
        # ensure the rp has the backup tag, to avoid deleting rps not belonging to the the backup process
        if tag_value == BACKUP.list_tags(ResourceArn=rp)['Tags'].get(tag_key, None):
            BACKUP.delete_recovery_point(BackupVaultName=vaultname,
                                         RecoveryPointArn=rp)
            print('RecoveryPoint %s deleted' % rp)
        else:
            print('Skipping RecoveryPoint %s because it does not have the tag %s=%s' % (
                rp, tag_key, tag_value))


def list_ecr_tags(reponame):
    imagetags = {img['imageTag'] for img in paginate(
        ECR.list_images, repositoryName=reponame, filter={'tagStatus': 'TAGGED'})}
    return imagetags


{
    'imageDigest': 'string',
    'imageTag': 'string'
},


def delete_imgs(imgs, reponame):
    ECR.batch_delete_image(
        repositoryName=reponame,
        imageIds=[{'imageTag': t} for t in imgs]
    )
    print('Tags %s deleted' % imgs)


def clean_old_backups(bucket_name, backup_filename, novalue, db_identifier,  backup_vaultname, efs_arn, backup_tag, ecr_reponame, current_image_tag):
    refdb, reffs, refimg = get_references_tokeep(
        bucket_name, backup_filename, novalue)
    snaps = list_db_snapshots(db_identifier)
    tag_key = backup_tag.split('=')[0]
    tag_value = backup_tag.split('=')[-1]
    not_in_refdb = snaps - refdb
    if len(not_in_refdb) > 0:
        print('These DB snapshot are no longer referenced: %s ; Deleting...' %
              not_in_refdb)
        delete_snapshots(not_in_refdb, tag_key, tag_value)
    else:
        print('No DB snapshot to delete.')
    rps = list_efs_recoverypoints(backup_vaultname, efs_arn)
    not_in_reffs = rps - reffs
    if len(not_in_reffs) > 0:
        print('These EFS recoverypoints are no longer referenced: %s ; Deleting...' %
              not_in_reffs)
        delete_recoverypoints(
            not_in_reffs, backup_vaultname, tag_key, tag_value)
    else:
        print('No EFS recoverypoint to delete.')
    imgs = list_ecr_tags(ecr_reponame)
    not_in_refimg = imgs - refimg
    # don't delete the current tag:
    not_in_refimg.discard(current_image_tag)
    if len(not_in_refimg) > 0:
        print('These ECR image tags are no longer referenced: %s ; Deleting...' %
              not_in_refimg)
        delete_imgs(not_in_refimg, ecr_reponame)
    else:
        print('No ECR image tag to delete.')


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("bucket_name")
    parser.add_argument("backup_filename")
    parser.add_argument("db_identifier")
    parser.add_argument("backup_vaultname")
    parser.add_argument("efs_arn")
    parser.add_argument("backup_tag")
    parser.add_argument("ecr_reponame")
    parser.add_argument("current_image_tag")
    parser.add_argument("--novaluestring", default='NONE')
    args = parser.parse_args()
    clean_old_backups(args.bucket_name,
                      args.backup_filename,
                      args.novaluestring,
                      args.db_identifier,
                      args.backup_vaultname,
                      args.efs_arn,
                      args.backup_tag,
                      args.ecr_reponame,
                      args.current_image_tag)
