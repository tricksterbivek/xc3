
import boto3
import http.client
import json
import urllib.parse
import logging
import time
from datetime import date, timedelta

# Initialize boto3 clients
ec2_client = boto3.client("ec2")
s3 = boto3.client("s3")
cost_client = boto3.client('ce', region_name=region)

def get_cost_and_usage_data(client, start, end, region, account_id):
    while True:
        try:
            response = client.get_cost_and_usage(
                TimePeriod={"Start": start, "End": end},
                Granularity="MONTHLY",
                Metrics=["UnblendedCost"],
                GroupBy=[{"Type": "DIMENSION", "Key": "SERVICE"}],
                Filter={
                    "And": [
                        {"Dimensions": {"Key": "REGION", "Values": [region]}},
                        {"Dimensions": {"Key": "LINKED_ACCOUNT", "Values": [account_id]}},
                    ]
                },
            )
            return response
        except client.exceptions.LimitExceededException:
            time.sleep(5)
        except ValueError as ve:
            raise ValueError(f"ValueError occurred: {ve}.\nPlease check the input data format.")

def send_slack_notification(cost, detailed_costs):
    slack_webhook_url = urllib.parse.urlparse(slack_webhook_url)
    cost_details = '\n'.join([f"{item['Service']}: `${float(item['Cost'])}`" for item in detailed_costs])

    slack_message = {
        'blocks': [
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": "*AWS Price Alert*"
                }
            },
            {
                "type": "divider"
            },
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f"*Total Cost:* `${cost:.2f}`\n\n*Breakdown:*\n{cost_details}"
                }
            }
        ]
    }

    conn = http.client.HTTPSConnection(slack_webhook_url.netloc)
    try:
        conn.request(
            "POST",
            slack_webhook_url.path,
            body=json.dumps(slack_message),
            headers={'Content-Type': 'application/json'}
        )

        res = conn.getresponse()
        logging.info(f'Slack API response status: {res.status}')
    except Exception as e:
        logging.error("Failed to send slack notification.")
        logging.error(f"Error: {str(e)}")

def lambda_handler(event, context):
    account_id = "208662306814"
    account_detail = "teamg"

    # Calculate the total cost for the month
    cost_threshold = 1
    response = cost_client.get_cost_and_usage(
        TimePeriod={
            'Start': '2023-07-01',
            'End': '2023-08-12'
        },
        Granularity='MONTHLY',
        Metrics=['UnblendedCost']
    )

    total_cost = float(response['ResultsByTime'][0]['Total']['UnblendedCost']['Amount'])

    # Compute the distributed costs
    end_date = str(date.today())
    start_date = str(date.today() - timedelta(days=1))
    parent_list = []

    # Get all AWS regions
    try:
        regions = [region["RegionName"] for region in ec2_client.describe_regions()["Regions"]]
    except Exception as e:
        logging.error(f"Error getting regions: {e}")

    for region in regions:
        ce_region = boto3.client("ce", region_name=region)
        try:
            cost_and_usage = get_cost_and_usage_data(ce_region, start_date, end_date, region, account_id)
            cost_data = cost_and_usage["ResultsByTime"][0]["Groups"]
            top_5_resources = sorted(cost_data, key=lambda x: x["Metrics"]["UnblendedCost"]["Amount"], reverse=True)[:5]
            for resource in top_5_resources:
                resourcedata = {
                    "Account": account_detail,
                    "Region": region,
                    "Service": resource["Keys"][0],
                    "Cost": resource["Metrics"]["UnblendedCost"]["Amount"],
                }
                parent_list.append(resourcedata)
        except Exception as e:
            logging.error(f"Error processing region {region}: {e}")

    if total_cost > cost_threshold:
        send_email(total_cost, parent_list)
        send_slack_notification(total_cost, parent_list)

    return {
        "statusCode": 200, 
        "body": json.dumps({
            "total_cost": total_cost,
            "distributed_costs": parent_list
        })
    }




def send_email(total_cost, distributed_costs):
    # Email Notification
    ses = boto3.client('ses', region_name='ap-southeast-2')
    
    # Formatting the detailed costs for the email body
    detailed_cost_string = "\n".join([
        f"{item['Service']} in {item['Region']}: ${float(item['Cost']):.2f}" 
        for item in distributed_costs
    ])

    email_body = f"Total AWS Cost: ${total_cost:.2f}\n\nCost Breakdown:\n{detailed_cost_string}"

    try:
        ses.send_email(
            Source= Creator,
            Destination={
                'ToAddresses': [
                    'belike0077@gmail.com'
                ]
            },
            Message={
                'Subject': {
                    'Data': 'AWS Alert - Cost Exceed Alert',
                    'Charset': 'UTF-8'
                },
                'Body': {
                    'Text': {
                        'Data': email_body,
                        'Charset': 'UTF-8'
                    }
                }
            }
        )
        print("Email sent successfully.")
    except Exception as e:
        print("Failed to send email.")
        print(f"Error: {str(e)}")

    