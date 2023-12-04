from __future__ import print_function
import os
import boto3

client = boto3.client('eks')

def handler(event, context):
    cluster = os.getenv("cluster", None)
    region = os.getenv("region", None)

    if cluster and region:
        message = "Env vars are there cluster: {} region: {}!".format(cluster, region)
        # List Node Groups inside cluster
        response = client.list_nodegroups(
            clusterName=cluster,
        )
        try:
            for nodegroup in response['nodegroups']:
                print("Node Group => {}".format(nodegroup))
                response = client.update_nodegroup_version(
                    clusterName=cluster,
                    nodegroupName=nodegroup,
                )
                message = "Update => {}".format(response)
        except:
            message = "Something went badly wrong, do you have Managed Node groups in this cluster?"
    else:
        message = "No env vars passed"

    print(message)
    return message
