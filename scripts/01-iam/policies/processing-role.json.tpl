{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowS3ProcessingDataAccess",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:GetObjectVersion", "s3:ListBucket", "s3:GetBucketLocation"],
      "Resource": [
        "arn:aws:s3:::${COMPANY}-sm-${TEAM}-${PROJECT}",
        "arn:aws:s3:::${COMPANY}-sm-${TEAM}-${PROJECT}/data/*",
        "arn:aws:s3:::${COMPANY}-sm-${TEAM}-${PROJECT}/raw/*",
        "arn:aws:s3:::${COMPANY}-sm-${TEAM}-${PROJECT}/datasets/*"
      ]
    },
    {
      "Sid": "AllowS3ProcessingOutput",
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:DeleteObject", "s3:GetObject"],
      "Resource": [
        "arn:aws:s3:::${COMPANY}-sm-${TEAM}-${PROJECT}/processed/*",
        "arn:aws:s3:::${COMPANY}-sm-${TEAM}-${PROJECT}/features/*",
        "arn:aws:s3:::${COMPANY}-sm-${TEAM}-${PROJECT}/processing-output/*"
      ]
    },
    {
      "Sid": "AllowS3SageMakerDefaultBucket",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetBucketLocation"],
      "Resource": ["arn:aws:s3:::sagemaker-${AWS_REGION}-${AWS_ACCOUNT_ID}", "arn:aws:s3:::sagemaker-${AWS_REGION}-${AWS_ACCOUNT_ID}/*"]
    },
    {
      "Sid": "AllowSharedAssetsReadOnly",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": ["arn:aws:s3:::${COMPANY}-sm-shared-assets", "arn:aws:s3:::${COMPANY}-sm-shared-assets/*"]
    },
    {
      "Sid": "AllowCloudWatchLogs",
      "Effect": "Allow",
      "Action": ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams", "logs:GetLogEvents"],
      "Resource": ["arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/aws/sagemaker/ProcessingJobs/*"]
    },
    {
      "Sid": "AllowECRPull",
      "Effect": "Allow",
      "Action": ["ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage", "ecr:BatchCheckLayerAvailability", "ecr:DescribeRepositories", "ecr:ListImages"],
      "Resource": ["arn:aws:ecr:${AWS_REGION}:${AWS_ACCOUNT_ID}:repository/${COMPANY}-sm-*"]
    },
    {
      "Sid": "AllowECRAuth",
      "Effect": "Allow",
      "Action": "ecr:GetAuthorizationToken",
      "Resource": "*"
    },
    {
      "Sid": "AllowECRPullAWSImages",
      "Effect": "Allow",
      "Action": ["ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage", "ecr:BatchCheckLayerAvailability"],
      "Resource": "*"
    },
    {
      "Sid": "AllowVPCNetworkInterface",
      "Effect": "Allow",
      "Action": ["ec2:CreateNetworkInterface", "ec2:CreateNetworkInterfacePermission", "ec2:DeleteNetworkInterface", "ec2:DeleteNetworkInterfacePermission", "ec2:DescribeNetworkInterfaces", "ec2:DescribeVpcs", "ec2:DescribeDhcpOptions", "ec2:DescribeSubnets", "ec2:DescribeSecurityGroups"],
      "Resource": "*"
    }
  ]
}
