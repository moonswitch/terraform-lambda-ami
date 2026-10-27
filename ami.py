from __future__ import print_function
import os
import boto3
import json
import requests

def SendWebhookNotification(webhookURL, updateDetails):
    headers = {"Content-Type": "application/json"}
    response = requests.post(webhookURL, data=json.dumps(updateDetails, default=str), headers=headers)
    return response.status_code

def lambda_handler(event, context):
    client = boto3.client('eks')
    
    cluster = os.getenv("cluster")
    region = os.getenv("region")
    webhookURL = os.getenv("webhook-url")

    if cluster and region:
        message = "Cluster: {} Region: {}".format(cluster, region)
        try:
            response = client.list_nodegroups(clusterName=cluster)
            for nodegroup in response["nodegroups"]:
                print("Node Group => {}".format(nodegroup))
                update_response = client.update_nodegroup_version(
                    clusterName=cluster,
                    nodegroupName=nodegroup,
                )

                updateDetails = {
                    "cluster": cluster,
                    "nodegroup": nodegroup,
                    "update-status": update_response["update"]["status"],
                    "details": update_response
                }
                message = "Update => {}".format(updateDetails)
                print(message)

                if webhookURL:
                    SendWebhookNotification(webhookURL, updateDetails)

        except Exception as e:
            message = "Something went badly wrong: {}".format(e)
            print(message)

            if webhookURL:
                errorDetails = {
                    "cluster": cluster,
                    "error": str(e),
                    "details": "An error occurred during the update process."
                }
                SendWebhookNotification(webhookURL, errorDetails)
            
    else:
        message = "No env vars passed"
    

    return {
        "statusCode": 200
    }
