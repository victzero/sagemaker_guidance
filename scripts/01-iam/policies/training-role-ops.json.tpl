{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowTrainingOperations",
      "Effect": "Allow",
      "Action": [
        "sagemaker:CreateTrainingJob", "sagemaker:DescribeTrainingJob", "sagemaker:StopTrainingJob", "sagemaker:ListTrainingJobs",
        "sagemaker:CreateHyperParameterTuningJob", "sagemaker:DescribeHyperParameterTuningJob", "sagemaker:StopHyperParameterTuningJob",
        "sagemaker:ListHyperParameterTuningJobs", "sagemaker:ListTrainingJobsForHyperParameterTuningJob", "sagemaker:AddTags", "sagemaker:ListTags"
      ],
      "Resource": [
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:training-job/${TEAM}-${PROJECT}-*",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:hyper-parameter-tuning-job/${TEAM}-${PROJECT}-*"
      ]
    },
    {
      "Sid": "AllowModelRegistryWrite",
      "Effect": "Allow",
      "Action": ["sagemaker:CreateModelPackage", "sagemaker:CreateModelPackageGroup", "sagemaker:DescribeModelPackage", "sagemaker:DescribeModelPackageGroup", "sagemaker:ListModelPackages", "sagemaker:UpdateModelPackage"],
      "Resource": [
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:model-package-group/${TEAM}-${PROJECT}",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:model-package/${TEAM}-${PROJECT}/*"
      ]
    },
    {
      "Sid": "AllowExperimentTracking",
      "Effect": "Allow",
      "Action": [
        "sagemaker:CreateExperiment", "sagemaker:DescribeExperiment", "sagemaker:UpdateExperiment", "sagemaker:DeleteExperiment",
        "sagemaker:CreateTrial", "sagemaker:DescribeTrial", "sagemaker:UpdateTrial", "sagemaker:DeleteTrial",
        "sagemaker:CreateTrialComponent", "sagemaker:DescribeTrialComponent", "sagemaker:UpdateTrialComponent", "sagemaker:DeleteTrialComponent",
        "sagemaker:AssociateTrialComponent", "sagemaker:DisassociateTrialComponent"
      ],
      "Resource": [
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:experiment/${TEAM}-${PROJECT}-*",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:experiment-trial/${TEAM}-${PROJECT}-*",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:experiment-trial-component/${TEAM}-${PROJECT}-*"
      ]
    },
    {
      "Sid": "AllowPassRoleToSageMaker",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/SageMaker-${TEAM_FULLNAME}-${PROJECT_FULLNAME}-TrainingRole",
      "Condition": {"StringEquals": {"iam:PassedToService": "sagemaker.amazonaws.com"}}
    },
    {
      "Sid": "AllowKMSForTraining",
      "Effect": "Allow",
      "Action": ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey"],
      "Resource": "arn:aws:kms:${AWS_REGION}:${AWS_ACCOUNT_ID}:key/*",
      "Condition": {"StringLike": {"kms:ViaService": "sagemaker.${AWS_REGION}.amazonaws.com"}}
    }
  ]
}

