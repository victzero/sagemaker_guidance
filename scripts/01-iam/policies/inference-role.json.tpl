{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowS3ModelReadOnly",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::${COMPANY}-sm-${TEAM}-${PROJECT}",
        "arn:aws:s3:::${COMPANY}-sm-${TEAM}-${PROJECT}/models/*",
        "arn:aws:s3:::${COMPANY}-sm-${TEAM}-${PROJECT}/inference/*"
      ]
    },
    {
      "Sid": "AllowS3InferenceOutput",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::${COMPANY}-sm-${TEAM}-${PROJECT}/inference/output/*",
        "arn:aws:s3:::${COMPANY}-sm-${TEAM}-${PROJECT}/batch-transform/*"
      ]
    },
    {
      "Sid": "AllowS3SageMakerDefaultBucketReadOnly",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
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
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ],
      "Resource": [
        "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/aws/sagemaker/Endpoints/*",
        "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/aws/sagemaker/InferenceRecommendationsJobs/*",
        "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/aws/sagemaker/TransformJobs/*"
      ]
    },
    {
      "Sid": "AllowECRPullOnly",
      "Effect": "Allow",
      "Action": [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability",
        "ecr:DescribeRepositories",
        "ecr:ListImages"
      ],
      "Resource": [
        "arn:aws:ecr:${AWS_REGION}:${AWS_ACCOUNT_ID}:repository/${COMPANY}-sm-*",
        "arn:aws:ecr:${AWS_REGION}:${AWS_ACCOUNT_ID}:repository/${COMPANY}-sagemaker-shared/*"
      ]
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
      "Sid": "AllowModelRegistryReadOnly",
      "Effect": "Allow",
      "Action": [
        "sagemaker:DescribeModelPackage",
        "sagemaker:DescribeModelPackageGroup",
        "sagemaker:ListModelPackages",
        "sagemaker:ListModelPackageGroups"
      ],
      "Resource": [
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:model-package-group/${TEAM}-${PROJECT}",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:model-package/${TEAM}-${PROJECT}/*"
      ]
    },
    {
      "Sid": "AllowInferenceOperations",
      "Effect": "Allow",
      "Action": [
        "sagemaker:CreateModel",
        "sagemaker:DeleteModel",
        "sagemaker:DescribeModel",
        "sagemaker:ListModels",
        "sagemaker:CreateEndpointConfig",
        "sagemaker:DeleteEndpointConfig",
        "sagemaker:DescribeEndpointConfig",
        "sagemaker:ListEndpointConfigs",
        "sagemaker:CreateEndpoint",
        "sagemaker:DeleteEndpoint",
        "sagemaker:UpdateEndpoint",
        "sagemaker:DescribeEndpoint",
        "sagemaker:ListEndpoints",
        "sagemaker:InvokeEndpoint",
        "sagemaker:InvokeEndpointAsync",
        "sagemaker:CreateTransformJob",
        "sagemaker:DescribeTransformJob",
        "sagemaker:StopTransformJob",
        "sagemaker:ListTransformJobs",
        "sagemaker:CreateInferenceRecommendationsJob",
        "sagemaker:DescribeInferenceRecommendationsJob",
        "sagemaker:StopInferenceRecommendationsJob"
      ],
      "Resource": [
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:model/${TEAM}-${PROJECT}-*",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:endpoint-config/${TEAM}-${PROJECT}-*",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:endpoint/${TEAM}-${PROJECT}-*",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:transform-job/${TEAM}-${PROJECT}-*",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:inference-recommendations-job/${TEAM}-${PROJECT}-*"
      ]
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
      "Sid": "AllowPassRoleToSageMaker",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/SageMaker-${TEAM_FULLNAME}-${PROJECT_FULLNAME}-InferenceRole",
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": "sagemaker.amazonaws.com"
        }
      }
    }
  ]
}

