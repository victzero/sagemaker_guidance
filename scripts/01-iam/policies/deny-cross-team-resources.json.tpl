{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyDeleteOtherTeamModels",
      "Effect": "Deny",
      "Action": [
        "sagemaker:DeleteModel"
      ],
      "NotResource": "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:model/${TEAM}-*"
    },
    {
      "Sid": "DenyDeleteOtherTeamEndpointConfigs",
      "Effect": "Deny",
      "Action": [
        "sagemaker:DeleteEndpointConfig"
      ],
      "NotResource": "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:endpoint-config/${TEAM}-*"
    },
    {
      "Sid": "DenyModifyOtherTeamEndpoints",
      "Effect": "Deny",
      "Action": [
        "sagemaker:DeleteEndpoint",
        "sagemaker:UpdateEndpoint",
        "sagemaker:UpdateEndpointWeightsAndCapacities"
      ],
      "NotResource": "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:endpoint/${TEAM}-*"
    },
    {
      "Sid": "DenyInvokeOtherTeamEndpoints",
      "Effect": "Deny",
      "Action": [
        "sagemaker:InvokeEndpoint",
        "sagemaker:InvokeEndpointAsync",
        "sagemaker:InvokeEndpointWithResponseStream"
      ],
      "NotResource": "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:endpoint/${TEAM}-*"
    },
    {
      "Sid": "DenyStopOtherTeamTransformJobs",
      "Effect": "Deny",
      "Action": [
        "sagemaker:StopTransformJob"
      ],
      "NotResource": "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:transform-job/${TEAM}-*"
    },
    {
      "Sid": "DenyStopOtherTeamTrainingJobs",
      "Effect": "Deny",
      "Action": [
        "sagemaker:StopTrainingJob"
      ],
      "NotResource": "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:training-job/${TEAM}-*"
    },
    {
      "Sid": "DenyStopOtherTeamProcessingJobs",
      "Effect": "Deny",
      "Action": [
        "sagemaker:StopProcessingJob"
      ],
      "NotResource": "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:processing-job/${TEAM}-*"
    },
    {
      "Sid": "DenyStopOtherTeamHPOJobs",
      "Effect": "Deny",
      "Action": [
        "sagemaker:StopHyperParameterTuningJob"
      ],
      "NotResource": "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:hyper-parameter-tuning-job/${TEAM}-*"
    },
    {
      "Sid": "DenyModifyOtherTeamExperiments",
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
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:experiment/${TEAM}-*",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:experiment-trial/${TEAM}-*",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:experiment-trial-component/${TEAM}-*"
      ]
    },
    {
      "Sid": "DenyModifyOtherTeamModelPackages",
      "Effect": "Deny",
      "Action": [
        "sagemaker:DeleteModelPackage",
        "sagemaker:UpdateModelPackage",
        "sagemaker:DeleteModelPackageGroup"
      ],
      "NotResource": [
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:model-package/${TEAM}-*",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:model-package-group/${TEAM}-*"
      ]
    }
  ]
}
