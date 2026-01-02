{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyAllWithoutMFA",
      "Effect": "Deny",
      "NotAction": [
        "iam:CreateVirtualMFADevice",
        "iam:DeleteVirtualMFADevice",
        "iam:EnableMFADevice",
        "iam:ListMFADevices",
        "iam:ListVirtualMFADevices",
        "iam:ResyncMFADevice",
        "iam:DeactivateMFADevice",
        "iam:GetUser",
        "iam:ChangePassword",
        "iam:GetAccountPasswordPolicy",
        "sts:GetCallerIdentity"
      ],
      "Resource": "*",
      "Condition": {
        "BoolIfExists": {
          "aws:MultiFactorAuthPresent": "false"
        }
      }
    },
    {
      "Sid": "DenyS3BucketListing",
      "Effect": "Deny",
      "Action": "s3:ListAllMyBuckets",
      "Resource": "*"
    },
    {
      "Sid": "DenyAccessToOtherBuckets",
      "Effect": "Deny",
      "Action": "s3:*",
      "NotResource": [
        "arn:aws:s3:::${COMPANY}-sm-*",
        "arn:aws:s3:::${COMPANY}-sm-*/*",
        "arn:aws:s3:::sagemaker-${AWS_REGION}-${AWS_ACCOUNT_ID}",
        "arn:aws:s3:::sagemaker-${AWS_REGION}-${AWS_ACCOUNT_ID}/*"
      ]
    },
    {
      "Sid": "AllowSageMakerFullAccess",
      "Effect": "Allow",
      "Action": "sagemaker:*",
      "Resource": "*"
    },
    {
      "Sid": "AllowS3SageMakerBuckets",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts"
      ],
      "Resource": [
        "arn:aws:s3:::${COMPANY}-sm-*",
        "arn:aws:s3:::${COMPANY}-sm-*/*",
        "arn:aws:s3:::sagemaker-${AWS_REGION}-${AWS_ACCOUNT_ID}",
        "arn:aws:s3:::sagemaker-${AWS_REGION}-${AWS_ACCOUNT_ID}/*"
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
      "Sid": "AllowViewAccountPasswordPolicy",
      "Effect": "Allow",
      "Action": [
        "iam:GetAccountPasswordPolicy",
        "iam:ListVirtualMFADevices"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowSelfServiceIAM",
      "Effect": "Allow",
      "Action": [
        "iam:ChangePassword",
        "iam:GetUser",
        "iam:CreateVirtualMFADevice",
        "iam:DeleteVirtualMFADevice",
        "iam:EnableMFADevice",
        "iam:ListMFADevices",
        "iam:ResyncMFADevice",
        "iam:DeactivateMFADevice"
      ],
      "Resource": [
        "arn:aws:iam::${AWS_ACCOUNT_ID}:user${IAM_PATH}*",
        "arn:aws:iam::${AWS_ACCOUNT_ID}:mfa/*"
      ]
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

