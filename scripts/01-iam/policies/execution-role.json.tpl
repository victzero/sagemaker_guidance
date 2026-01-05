{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowS3ProjectAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::${COMPANY}-sm-${TEAM}-${PROJECT}",
        "arn:aws:s3:::${COMPANY}-sm-${TEAM}-${PROJECT}/*"
      ]
    },
    {
      "Sid": "AllowS3SageMakerDefaultBucket",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::sagemaker-${AWS_REGION}-${AWS_ACCOUNT_ID}",
        "arn:aws:s3:::sagemaker-${AWS_REGION}-${AWS_ACCOUNT_ID}/*"
      ]
    },
    {
      "Sid": "AllowSharedAssetsReadOnly",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${COMPANY}-sm-shared-assets",
        "arn:aws:s3:::${COMPANY}-sm-shared-assets/*"
      ]
    },
    {
      "Sid": "AllowCloudWatchLogs",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/aws/sagemaker/*"
    },
    {
      "Sid": "AllowECRReadWrite",
      "Effect": "Allow",
      "Action": [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability",
        "ecr:CreateRepository",
        "ecr:DescribeRepositories",
        "ecr:ListImages",
        "ecr:BatchDeleteImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage"
      ],
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
      "Action": [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowDataScienceAssistant",
      "Effect": "Allow",
      "Action": [
        "sagemaker-data-science-assistant:SendConversation"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:ResourceAccount": "${AWS_ACCOUNT_ID}"
        }
      }
    },
    {
      "Sid": "AllowAmazonQDeveloper",
      "Effect": "Allow",
      "Action": [
        "q:SendMessage",
        "q:StartConversation"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:ResourceAccount": "${AWS_ACCOUNT_ID}"
        }
      }
    },
    {
      "Sid": "AllowVPCNetworkInterface",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateNetworkInterface",
        "ec2:CreateNetworkInterfacePermission",
        "ec2:DeleteNetworkInterface",
        "ec2:DeleteNetworkInterfacePermission",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DescribeVpcs",
        "ec2:DescribeDhcpOptions",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowModelRegistry",
      "Effect": "Allow",
      "Action": [
        "sagemaker:CreateModelPackage",
        "sagemaker:CreateModelPackageGroup",
        "sagemaker:DescribeModelPackage",
        "sagemaker:DescribeModelPackageGroup",
        "sagemaker:ListModelPackages",
        "sagemaker:ListModelPackageGroups",
        "sagemaker:UpdateModelPackage",
        "sagemaker:DeleteModelPackage"
      ],
      "Resource": [
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:model-package-group/${TEAM}-${PROJECT}",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:model-package/${TEAM}-${PROJECT}/*"
      ]
    }
  ]
}

