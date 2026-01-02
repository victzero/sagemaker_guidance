{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowDescribeDomain",
      "Effect": "Allow",
      "Action": [
        "sagemaker:DescribeDomain",
        "sagemaker:ListDomains"
      ],
      "Resource": "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:domain/*"
    },
    {
      "Sid": "AllowListUserProfiles",
      "Effect": "Allow",
      "Action": [
        "sagemaker:ListUserProfiles",
        "sagemaker:ListSpaces",
        "sagemaker:ListApps"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowListTags",
      "Effect": "Allow",
      "Action": [
        "sagemaker:ListTags",
        "sagemaker:AddTags"
      ],
      "Resource": [
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:domain/*",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:user-profile/*",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:space/*",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:app/*"
      ]
    },
    {
      "Sid": "AllowDescribeOwnProfile",
      "Effect": "Allow",
      "Action": [
        "sagemaker:DescribeUserProfile",
        "sagemaker:CreatePresignedDomainUrl"
      ],
      "Resource": "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:user-profile/*/*",
      "Condition": {
        "StringEquals": {
          "sagemaker:ResourceTag/Owner": "${aws:username}"
        }
      }
    }
  ]
}

