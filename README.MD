# Archived

Today, we have better solutions like [AWS Toolkit extension](https://aws.amazon.com/visualstudiocode/) that provides both debugging, build, and local invoke. 

## Requirements

* Software
    - [Python 3](https://www.python.org/downloads/)
    - [Docker](https://docs.docker.com/engine/installation/)
    - [SAM Local](https://github.com/awslabs/aws-sam-local)
* Linux or OSX    

## Quick start

We need to bootstrap our environment quickly in order to have both SAM Local and DynamoDB Local to play together nicely:

1) **Create a docker network**

```bash
docker network create sam-demo
```

2) **Run and Bootstrap DynamoDB Local**

> **You need to install boto3 and faker library to bootstrap dynamo (pip install faker boto3), or simply use AWS CLI**

```bash
docker run -d -v "$PWD":/dynamodb_local_db -p 8000:8000 --network sam-demo --name dynamodb cnadiminti/dynamodb-local
python bootstrap_dynamodb.py -t "users" --hash-key "id"
```

3) **Create local development environment and run**

```bash
make build-dev SERVICE="users"
sam local start-api --docker-network sam-demo
```

4) **Test API locally**

```bash
curl localhost:3000/getUsers
```
