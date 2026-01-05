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
      "Sid": "AllowInferenceOperations",
      "Effect": "Allow",
      "Action": [
        "sagemaker:CreateModel", "sagemaker:DeleteModel", "sagemaker:DescribeModel", "sagemaker:ListModels",
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
      "Resource": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/SageMaker-${TEAM_FULLNAME}-${PROJECT_FULLNAME}-InferenceRole",
      "Condition": {"StringEquals": {"iam:PassedToService": "sagemaker.amazonaws.com"}}
    }
  ]
}

