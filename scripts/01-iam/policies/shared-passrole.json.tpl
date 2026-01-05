{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyPassRoleToOtherProjects",
      "Effect": "Deny",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/SageMaker-*",
      "Condition": {
        "ArnNotLike": {
          "aws:ResourceArn": [
            "arn:aws:iam::${AWS_ACCOUNT_ID}:role/SageMaker-${TEAM_FULLNAME}-${PROJECT_FULLNAME}-*",
            "arn:aws:iam::${AWS_ACCOUNT_ID}:role/SageMaker-Domain-*"
          ]
        }
      }
    },
    {
      "Sid": "AllowPassRoleToProjectRoles",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": [
        "arn:aws:iam::${AWS_ACCOUNT_ID}:role/SageMaker-${TEAM_FULLNAME}-${PROJECT_FULLNAME}-ExecutionRole",
        "arn:aws:iam::${AWS_ACCOUNT_ID}:role/SageMaker-${TEAM_FULLNAME}-${PROJECT_FULLNAME}-TrainingRole",
        "arn:aws:iam::${AWS_ACCOUNT_ID}:role/SageMaker-${TEAM_FULLNAME}-${PROJECT_FULLNAME}-ProcessingRole",
        "arn:aws:iam::${AWS_ACCOUNT_ID}:role/SageMaker-${TEAM_FULLNAME}-${PROJECT_FULLNAME}-InferenceRole"
      ],
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": "sagemaker.amazonaws.com"
        }
      }
    },
    {
      "Sid": "AllowGetRole",
      "Effect": "Allow",
      "Action": [
        "iam:GetRole",
        "iam:ListRoles"
      ],
      "Resource": "*"
    }
  ]
}
