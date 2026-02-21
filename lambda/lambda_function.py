import json
import boto3
import os
import uuid
from datetime import datetime

dynamodb = boto3.resource("dynamodb")
sns = boto3.client("sns")
autoscaling = boto3.client("autoscaling")

table = dynamodb.Table(os.environ["TABLE_NAME"])
topic = os.environ["SNS_TOPIC"]
asg_name = os.environ["ASG_NAME"]

def get_in_service_instance_count():
    """
    Returns the number of InService instances currently running in the ASG.
    We call Auto Scaling API because EventBridge doesn't reliably include the full count.
    """
    resp = autoscaling.describe_auto_scaling_groups(
        AutoScalingGroupNames=[asg_name]
    )

    groups = resp.get("AutoScalingGroups", [])
    if not groups:
        return 0

    instances = groups[0].get("Instances", [])

    # Count only instances in lifecycle state "InService"
    in_service = [
        i for i in instances
        if i.get("LifecycleState") == "InService"
    ]
    return len(in_service)

def lambda_handler(event, context):
    event_id = str(uuid.uuid4())

    # Get current number of running instances in the ASG
    instance_count = get_in_service_instance_count()

    record = {
        "event_id": event_id,
        "time": datetime.utcnow().isoformat() + "Z",
        "detail_type": event.get("detail-type", "unknown"),
        "instance_id": event.get("detail", {}).get("EC2InstanceId", "unknown"),
        "asg_name": asg_name,
        "in_service_instance_count": instance_count
    }

    table.put_item(Item=record)

    sns.publish(
        TopicArn=topic,
        Subject="ASG Scaling Event",
        Message=json.dumps(record, indent=2)
    )

    return {"status": "logged", "record": record}
