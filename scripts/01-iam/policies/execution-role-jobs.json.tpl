{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowPassRoleToSpecializedRoles",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": [
        "arn:aws:iam::${AWS_ACCOUNT_ID}:role/SageMaker-${TEAM_FULLNAME}-${PROJECT_FULLNAME}-TrainingRole",
        "arn:aws:iam::${AWS_ACCOUNT_ID}:role/SageMaker-${TEAM_FULLNAME}-${PROJECT_FULLNAME}-ProcessingRole",
        "arn:aws:iam::${AWS_ACCOUNT_ID}:role/SageMaker-${TEAM_FULLNAME}-${PROJECT_FULLNAME}-InferenceRole"
      ],
      "Condition": {"StringEquals": {"iam:PassedToService": "sagemaker.amazonaws.com"}}
    },
    {
      "Sid": "AllowSubmitJobs",
      "Effect": "Allow",
      "Action": [
        "sagemaker:CreateTrainingJob", "sagemaker:DescribeTrainingJob", "sagemaker:StopTrainingJob", "sagemaker:ListTrainingJobs",
        "sagemaker:CreateHyperParameterTuningJob", "sagemaker:DescribeHyperParameterTuningJob", "sagemaker:StopHyperParameterTuningJob", "sagemaker:ListHyperParameterTuningJobs",
        "sagemaker:CreateProcessingJob", "sagemaker:DescribeProcessingJob", "sagemaker:StopProcessingJob", "sagemaker:ListProcessingJobs",
        "sagemaker:CreateModel", "sagemaker:DescribeModel", "sagemaker:DeleteModel", "sagemaker:ListModels",
        "sagemaker:CreateEndpointConfig", "sagemaker:DescribeEndpointConfig", "sagemaker:DeleteEndpointConfig", "sagemaker:ListEndpointConfigs",
        "sagemaker:CreateEndpoint", "sagemaker:DescribeEndpoint", "sagemaker:DeleteEndpoint", "sagemaker:UpdateEndpoint", "sagemaker:ListEndpoints", "sagemaker:InvokeEndpoint",
        "sagemaker:CreateTransformJob", "sagemaker:DescribeTransformJob", "sagemaker:StopTransformJob", "sagemaker:ListTransformJobs"
      ],
      "Resource": [
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:training-job/${TEAM}-${PROJECT}-*",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:hyper-parameter-tuning-job/${TEAM}-${PROJECT}-*",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:processing-job/${TEAM}-${PROJECT}-*",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:model/${TEAM}-${PROJECT}-*",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:endpoint-config/${TEAM}-${PROJECT}-*",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:endpoint/${TEAM}-${PROJECT}-*",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:transform-job/${TEAM}-${PROJECT}-*"
      ]
    },
    {
      "Sid": "AllowExperimentTracking",
      "Effect": "Allow",
      "Action": [
        "sagemaker:CreateExperiment", "sagemaker:DescribeExperiment", "sagemaker:UpdateExperiment", "sagemaker:DeleteExperiment", "sagemaker:ListExperiments",
        "sagemaker:CreateTrial", "sagemaker:DescribeTrial", "sagemaker:UpdateTrial", "sagemaker:DeleteTrial", "sagemaker:ListTrials",
        "sagemaker:CreateTrialComponent", "sagemaker:DescribeTrialComponent", "sagemaker:UpdateTrialComponent", "sagemaker:DeleteTrialComponent", "sagemaker:ListTrialComponents",
        "sagemaker:AssociateTrialComponent", "sagemaker:DisassociateTrialComponent", "sagemaker:Search"
      ],
      "Resource": [
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:experiment/${TEAM}-${PROJECT}-*",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:experiment-trial/${TEAM}-${PROJECT}-*",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:experiment-trial-component/*"
      ]
    },
    {
      "Sid": "AllowModelRegistry",
      "Effect": "Allow",
      "Action": ["sagemaker:CreateModelPackage", "sagemaker:CreateModelPackageGroup", "sagemaker:DescribeModelPackage", "sagemaker:DescribeModelPackageGroup", "sagemaker:ListModelPackages", "sagemaker:ListModelPackageGroups", "sagemaker:UpdateModelPackage", "sagemaker:DeleteModelPackage"],
      "Resource": [
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:model-package-group/${TEAM}-${PROJECT}",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:model-package/${TEAM}-${PROJECT}/*"
      ]
    }
  ]
}

