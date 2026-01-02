{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowSageMakerFullAccess",
      "Effect": "Allow",
      "Action": "sagemaker:*",
      "Resource": "*"
    },
    {
      "Sid": "AllowS3SageMakerBuckets",
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::${COMPANY}-sm-*",
        "arn:aws:s3:::${COMPANY}-sm-*/*",
        "arn:aws:s3:::sagemaker-*",
        "arn:aws:s3:::sagemaker-*/*"
      ]
    },
    {
      "Sid": "AllowSupportingServices",
      "Effect": "Allow",
      "Action": [
        "ecr:*",
        "logs:*",
        "cloudwatch:*",
        "ec2:Describe*",
        "kms:Describe*",
        "kms:List*",
        "sts:GetCallerIdentity",
        "sts:AssumeRole",
        "glue:*",
        "athena:*",
        "codecommit:*",
        "secretsmanager:GetSecretValue",
        "servicecatalog:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowPassRoleToSageMaker",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/SageMaker-*",
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
    },
    {
      "Sid": "DenyDangerousIAMActions",
      "Effect": "Deny",
      "Action": [
        "iam:CreateUser",
        "iam:DeleteUser",
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:AttachUserPolicy",
        "iam:DetachUserPolicy",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:PutUserPolicy",
        "iam:DeleteUserPolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:CreatePolicy",
        "iam:DeletePolicy",
        "iam:CreatePolicyVersion",
        "iam:DeletePolicyVersion",
        "iam:PutUserPermissionsBoundary",
        "iam:DeleteUserPermissionsBoundary",
        "iam:PutRolePermissionsBoundary",
        "iam:DeleteRolePermissionsBoundary"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DenySageMakerAdminActions",
      "Effect": "Deny",
      "Action": [
        "sagemaker:CreateDomain",
        "sagemaker:DeleteDomain",
        "sagemaker:UpdateDomain",
        "sagemaker:CreateUserProfile",
        "sagemaker:DeleteUserProfile"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DenyS3BucketAdmin",
      "Effect": "Deny",
      "Action": [
        "s3:CreateBucket",
        "s3:DeleteBucket",
        "s3:PutBucketPolicy",
        "s3:DeleteBucketPolicy"
      ],
      "Resource": "*"
    }
  ]
}

