{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowDescribeTeamSpaces",
      "Effect": "Allow",
      "Action": [
        "sagemaker:DescribeSpace",
        "sagemaker:ListApps"
      ],
      "Resource": "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:space/*",
      "Condition": {
        "StringEquals": {
          "sagemaker:ResourceTag/Team": "${TEAM}"
        }
      }
    },
    {
      "Sid": "AllowListTeamS3Buckets",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": "arn:aws:s3:::${COMPANY}-sm-${TEAM}-*"
    }
  ]
}

