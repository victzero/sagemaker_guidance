{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyDeleteOtherProjectModels",
      "Effect": "Deny",
      "Action": [
        "sagemaker:DeleteModel"
      ],
      "NotResource": "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:model/${TEAM}-${PROJECT}-*"
    },
    {
      "Sid": "DenyDeleteOtherProjectEndpointConfigs",
      "Effect": "Deny",
      "Action": [
        "sagemaker:DeleteEndpointConfig"
      ],
      "NotResource": "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:endpoint-config/${TEAM}-${PROJECT}-*"
    },
    {
      "Sid": "DenyModifyOtherProjectEndpoints",
      "Effect": "Deny",
      "Action": [
        "sagemaker:DeleteEndpoint",
        "sagemaker:UpdateEndpoint",
        "sagemaker:UpdateEndpointWeightsAndCapacities"
      ],
      "NotResource": "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:endpoint/${TEAM}-${PROJECT}-*"
    },
    {
      "Sid": "DenyStopOtherProjectTransformJobs",
      "Effect": "Deny",
      "Action": [
        "sagemaker:StopTransformJob"
      ],
      "NotResource": "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:transform-job/${TEAM}-${PROJECT}-*"
    },
    {
      "Sid": "DenyStopOtherProjectTrainingJobs",
      "Effect": "Deny",
      "Action": [
        "sagemaker:StopTrainingJob"
      ],
      "NotResource": "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:training-job/${TEAM}-${PROJECT}-*"
    },
    {
      "Sid": "DenyStopOtherProjectProcessingJobs",
      "Effect": "Deny",
      "Action": [
        "sagemaker:StopProcessingJob"
      ],
      "NotResource": "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:processing-job/${TEAM}-${PROJECT}-*"
    },
    {
      "Sid": "DenyStopOtherProjectHPOJobs",
      "Effect": "Deny",
      "Action": [
        "sagemaker:StopHyperParameterTuningJob"
      ],
      "NotResource": "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:hyper-parameter-tuning-job/${TEAM}-${PROJECT}-*"
    },
    {
      "Sid": "DenyModifyOtherProjectExperiments",
      "Effect": "Deny",
      "Action": [
        "sagemaker:DeleteExperiment",
        "sagemaker:UpdateExperiment",
        "sagemaker:DeleteTrial",
        "sagemaker:UpdateTrial",
        "sagemaker:DeleteTrialComponent",
        "sagemaker:UpdateTrialComponent"
      ],
      "NotResource": [
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:experiment/${TEAM}-${PROJECT}-*",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:experiment-trial/${TEAM}-${PROJECT}-*",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:experiment-trial-component/${TEAM}-${PROJECT}-*"
      ]
    },
    {
      "Sid": "DenyModifyOtherProjectModelPackages",
      "Effect": "Deny",
      "Action": [
        "sagemaker:DeleteModelPackage",
        "sagemaker:UpdateModelPackage",
        "sagemaker:DeleteModelPackageGroup"
      ],
      "NotResource": [
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:model-package/${TEAM}-${PROJECT}/*",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:model-package-group/${TEAM}-${PROJECT}"
      ]
    }
  ]
}
