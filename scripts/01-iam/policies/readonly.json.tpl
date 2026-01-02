{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyS3BucketListing",
      "Effect": "Deny",
      "Action": "s3:ListAllMyBuckets",
      "Resource": "*"
    },
    {
      "Sid": "AllowSageMakerReadOnly",
      "Effect": "Allow",
      "Action": [
        "sagemaker:Describe*",
        "sagemaker:List*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowS3ReadOnlyCompanyBuckets",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::${COMPANY}-sm-*",
        "arn:aws:s3:::${COMPANY}-sm-*/*",
        "arn:aws:s3:::sagemaker-${AWS_REGION}-${AWS_ACCOUNT_ID}",
        "arn:aws:s3:::sagemaker-${AWS_REGION}-${AWS_ACCOUNT_ID}/*"
      ]
    },
    {
      "Sid": "AllowCloudWatchLogsReadOnly",
      "Effect": "Allow",
      "Action": [
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:GetLogEvents"
      ],
      "Resource": "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/aws/sagemaker/*"
    }
  ]
}

