import os
import boto3
from botocore.exceptions import ClientError
from boto3.dynamodb.conditions import Key
import json
import uuid

class NoTableName(Exception):
    pass

# Quick sanity checks and predefined local dev
if os.getenv("AWS_SAM_LOCAL", ""):
    ddb = boto3.resource('dynamodb',
                         endpoint_url="http://dynamodb:8000")
    ddb_table = "users"
    # ret = requests.get("https://google.com")
    # print("Status --> ", ret.text)
else:
    ddb = boto3.resource('dynamodb')
    ddb_table = os.getenv("TABLE_NAME", None)

if not ddb_table:
    raise NoTableName("Please double check SAM envs")
else:
    table = ddb.Table(ddb_table)


def lambda_handler(event, context):
    path = event["requestContext"]["resourcePath"]
    method = event["httpMethod"]

    if not ddb_table:
        raise NoTableName("DynamoDB Table Name not set...")

    # When time allows....
    # This should be a dispatcher
    # That would check for input validation
    # And would marshal data before-hand (event['body'])

    if path == "/getUsers" and method == "GET":
        return get_all_users(event)

    if not this_exist_not_null(event["body"]):
        return respond("Invalid parameters", 400)
    elif path == "/getUser" and method == "GET":
        return get_user(event)
    elif path == "/deleteUser" and method == "DELETE":
        return delete_user(event)
    elif path == "/updateUser" and method == "POST":
        return update_user(event)
    elif path == "/addUser" and method == "PUT":
        return add_user(event)
    else:
        return respond("Not implemented", 501)


def get_all_users(event):
    """ Simple Scan with no paginators """
    try:
        ret = table.scan()
        return respond(data=ret["Items"], status=200)
    except ClientError as e:
        print(e)
        return respond(data="Operation failed", status=500)


def get_user(event):
    """ Quick Get Item with no paginators """
    data = json.loads(event["body"])
    userId = data.get('id', None)

    if not this_exist_not_null(userId):
        return respond("Invalid parameters", 400)

    try:
        ret = table.query(
            KeyConditionExpression=Key('id').eq(userId)
        )
        return respond(data=ret["Items"], status=200)
    except ClientError as e:
        print(e)
        return respond(data="Operation failed", status=500)


def add_user(event):
    """ Simple single Put item"""
    data = json.loads(event["body"])
    userEmail = data.get("email", "")
    userId = str(uuid.uuid4())

    if not this_exist_not_null(userEmail):
        return respond("Invalid parameters", 400)

    try:
        params = {
            "Item": {
                "id": userId,
                "email": userEmail
            }
        }
        ret = table.put_item(**params)

        if aws_request_was_successful(ret):
            return respond(f"User {userEmail} with ID {userId} added successfully.", 200) # NOQA
    except ClientError as e:
        print(e)
        return respond(data="Operation failed", status=500)


def delete_user(event):
    """ Quick Delete Item """
    data = json.loads(event["body"])
    userId = data.get('id', None)

    if not this_exist_not_null(userId):
        return respond("Invalid parameters", 400)

    try:
        ret = table.delete_item(
            Key={
                "id": userId
            }
        )

        if aws_request_was_successful(ret):
            return respond(f"User {userId} Deleted successfully.", 200)
    except ClientError as e:
        print(e)
        return respond(data="Operation failed", status=500)


def update_user(event):
    """ Simple Single Update """

    data = json.loads(event["body"])
    userId = data.get('id', None)
    userEmail = data.get('email', None)

    if (
           not this_exist_not_null(userId) or
           not this_exist_not_null(userEmail)
       ):
        return respond("Invalid parameters", 400)

    try:
        ret = table.update_item(
            Key={
                "id": userId
            },
            UpdateExpression='SET email = :newvalue',
            ExpressionAttributeValues={
                ':newvalue': userEmail
            }
        )
        if aws_request_was_successful(ret):
            return respond(f"User {userId} Updated successfully.", 200)
    except ClientError as e:
        print(e)
        return respond("Operation failed", 500)


def respond(data="", status=501):
    return {
        "statusCode": status,
        "body": json.dumps(data)
    }


def this_exist_not_null(param):
    """Check if parameter exists or not"""
    if (
           not param or
           len(param) < 1
       ):
        return False

    return True


def aws_request_was_successful(resp):
    """ Quick check to confirm whether headers exist """
    if (
            resp["ResponseMetadata"]["RequestId"] and
            resp["ResponseMetadata"]["HTTPStatusCode"] == 200
       ):
        return True

    return False
