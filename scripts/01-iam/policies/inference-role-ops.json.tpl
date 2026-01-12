{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowModelRegistryReadOnly",
      "Effect": "Allow",
      "Action": ["sagemaker:DescribeModelPackage", "sagemaker:DescribeModelPackageGroup", "sagemaker:ListModelPackages", "sagemaker:ListModelPackageGroups"],
      "Resource": [
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:model-package-group/${TEAM}-${PROJECT}",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:model-package/${TEAM}-${PROJECT}/*"
      ]
    },
    {
      "Sid": "AllowCreateModelWithVpcRestriction",
      "Effect": "Allow",
      "Action": ["sagemaker:CreateModel"],
      "Resource": ["arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:model/${TEAM}-${PROJECT}-*"],
      "Condition": {
        "ForAllValues:StringEquals": {
          "sagemaker:VpcSubnets": ["${PRIVATE_SUBNET_1_ID}", "${PRIVATE_SUBNET_2_ID}"],
          "sagemaker:VpcSecurityGroupIds": ["${SG_SAGEMAKER_STUDIO}"]
        },
        "Null": {
          "sagemaker:VpcSubnets": "false",
          "sagemaker:VpcSecurityGroupIds": "false"
        }
      }
    },
    {
      "Sid": "AllowInferenceOperationsExceptCreateModel",
      "Effect": "Allow",
      "Action": [
        "sagemaker:DeleteModel", "sagemaker:DescribeModel", "sagemaker:ListModels",
        "sagemaker:CreateEndpointConfig", "sagemaker:DeleteEndpointConfig", "sagemaker:DescribeEndpointConfig", "sagemaker:ListEndpointConfigs",
        "sagemaker:CreateEndpoint", "sagemaker:DeleteEndpoint", "sagemaker:UpdateEndpoint", "sagemaker:DescribeEndpoint", "sagemaker:ListEndpoints",
        "sagemaker:InvokeEndpoint", "sagemaker:InvokeEndpointAsync",
        "sagemaker:CreateTransformJob", "sagemaker:DescribeTransformJob", "sagemaker:StopTransformJob", "sagemaker:ListTransformJobs",
        "sagemaker:CreateInferenceRecommendationsJob", "sagemaker:DescribeInferenceRecommendationsJob", "sagemaker:StopInferenceRecommendationsJob"
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
      "Sid": "AllowPassRoleToSageMaker",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_PATH_NAME}SageMaker-${TEAM_FULLNAME}-${PROJECT_FULLNAME}-InferenceRole",
      "Condition": {"StringEquals": {"iam:PassedToService": "sagemaker.amazonaws.com"}}
    },
    {
      "Sid": "DenyCreateModelWithoutVpc",
      "Effect": "Deny",
      "Action": ["sagemaker:CreateModel"],
      "Resource": "*",
      "Condition": {
        "Null": {
          "sagemaker:VpcSubnets": "true"
        }
      }
    },
    {
      "Sid": "DenyCreateModelWithPublicSubnet",
      "Effect": "Deny",
      "Action": ["sagemaker:CreateModel"],
      "Resource": "*",
      "Condition": {
        "ForAnyValue:StringNotEquals": {
          "sagemaker:VpcSubnets": ["${PRIVATE_SUBNET_1_ID}", "${PRIVATE_SUBNET_2_ID}"]
        }
      }
    }
  ]
}

