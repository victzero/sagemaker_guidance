{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "MLFlowAppManagement",
      "Effect": "Allow",
      "Action": [
        "sagemaker:CallMlflowAppApi",
        "sagemaker:DeleteMlflowApp",
        "sagemaker:DescribeMlflowApp",
        "sagemaker:UpdateMlflowApp",
        "sagemaker:ListTags"
      ],
      "Resource": "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:mlflow-app/*"
    },
    {
      "Sid": "MLFlowAppManagementCreateAndList",
      "Effect": "Allow",
      "Action": [
        "sagemaker:CreateMlflowApp",
        "sagemaker:CreatePresignedMlflowAppUrl",
        "sagemaker:ListMlflowApps"
      ],
      "Resource": "*"
    },
    {
      "Sid": "MLFlowAppTaggingOnAppAndModelRegistry",
      "Effect": "Allow",
      "Action": "sagemaker:AddTags",
      "Resource": [
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:mlflow-app/*",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:model-package/*",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:model-package-group/*",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:model/*"
      ],
      "Condition": {
        "StringEquals": {
          "sagemaker:TaggingAction": [
            "CreateMlflowApp",
            "UpdateMlflowApp",
            "CreateModelPackage",
            "CreateModelPackageGroup",
            "DescribeModelPackageGroup",
            "UpdateModelPackage",
            "RegisterModel"
          ]
        }
      }
    },
    {
      "Sid": "MLFlowAppExecutionBucketPermissions",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:AbortMultipartUpload",
        "s3:GetBucketLocation",
        "s3:GetBucketCors",
        "s3:PutBucketCors"
      ],
      "Resource": [
        "arn:aws:s3:::sagemaker-*",
        "arn:aws:s3:::sagemaker-*/*"
      ],
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "true"
        },
        "StringEquals": {
          "aws:ResourceAccount": "${AWS_ACCOUNT_ID}"
        }
      }
    },
    {
      "Sid": "MLFlowAppExecutionModelRegistry",
      "Effect": "Allow",
      "Action": [
        "sagemaker:CreateModelPackage",
        "sagemaker:CreateModelPackageGroup",
        "sagemaker:UpdateModelPackage",
        "sagemaker:DescribeModelPackageGroup"
      ],
      "Resource": "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:*/*"
    },
    {
      "Sid": "PassRoleForMLflow",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/SageMaker-*",
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": "sagemaker.amazonaws.com"
        },
        "ArnLike": {
          "iam:AssociatedResourceArn": "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:mlflow-app/*"
        }
      }
    }
  ]
}

