{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCloudWatchLogs",
      "Effect": "Allow",
      "Action": ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogGroups", "logs:DescribeLogStreams", "logs:GetLogEvents", "logs:FilterLogEvents"],
      "Resource": ["arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/aws/sagemaker/*"]
    },
    {
      "Sid": "AllowECRReadWrite",
      "Effect": "Allow",
      "Action": ["ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage", "ecr:BatchCheckLayerAvailability", "ecr:CreateRepository", "ecr:DescribeRepositories", "ecr:ListImages", "ecr:BatchDeleteImage", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:TagResource"],
      "Resource": "arn:aws:ecr:${AWS_REGION}:${AWS_ACCOUNT_ID}:repository/${COMPANY}-sm-*"
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
    },
    {
      "Sid": "AllowAIAssistant",
      "Effect": "Allow",
      "Action": ["sagemaker-data-science-assistant:SendConversation", "q:SendMessage", "q:StartConversation"],
      "Resource": "*",
      "Condition": {"StringEquals": {"aws:ResourceAccount": "${AWS_ACCOUNT_ID}"}}
    }
  ]
}
