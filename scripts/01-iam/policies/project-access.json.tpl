{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowProjectSpaceAccess",
      "Effect": "Allow",
      "Action": [
        "sagemaker:DescribeSpace",
        "sagemaker:UpdateSpace",
        "sagemaker:CreateApp",
        "sagemaker:DeleteApp",
        "sagemaker:DescribeApp"
      ],
      "Resource": [
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:space/*/space-${TEAM}-${PROJECT}-*",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:app/*/*/*/*"
      ],
      "Condition": {
        "StringEquals": {
          "sagemaker:ResourceTag/Project": "${PROJECT}"
        }
      }
    },
    {
      "Sid": "AllowDescribeOwnUserProfile",
      "Effect": "Allow",
      "Action": [
        "sagemaker:DescribeUserProfile",
        "sagemaker:CreatePresignedDomainUrl"
      ],
      "Resource": "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:user-profile/*/profile-${TEAM}-${PROJECT}-*"
    }
  ]
}
