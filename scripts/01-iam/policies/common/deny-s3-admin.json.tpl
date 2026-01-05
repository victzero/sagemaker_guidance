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

