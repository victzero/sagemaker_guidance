{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowS3ProjectAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::${COMPANY}-sm-${TEAM}-${PROJECT}",
        "arn:aws:s3:::${COMPANY}-sm-${TEAM}-${PROJECT}/*"
      ]
    },
    {
      "Sid": "AllowSharedAssetsReadOnly",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${COMPANY}-sm-shared-assets",
        "arn:aws:s3:::${COMPANY}-sm-shared-assets/*"
      ]
    },
    {
      "Sid": "AllowS3SageMakerDefaultBucket",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::sagemaker-${AWS_REGION}-${AWS_ACCOUNT_ID}",
        "arn:aws:s3:::sagemaker-${AWS_REGION}-${AWS_ACCOUNT_ID}/*"
      ]
    }
  ]
}

