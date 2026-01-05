{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenySageMakerAdminActions",
      "Effect": "Deny",
      "Action": [
        "sagemaker:CreateDomain",
        "sagemaker:DeleteDomain",
        "sagemaker:UpdateDomain",
        "sagemaker:CreateUserProfile",
        "sagemaker:DeleteUserProfile",
        "sagemaker:CreateSpace",
        "sagemaker:UpdateSpace",
        "sagemaker:DeleteSpace"
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
        "s3:DeleteBucketPolicy",
        "s3:ListAllMyBuckets"
      ],
      "Resource": "*"
    }
  ]
}

