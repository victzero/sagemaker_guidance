{
  "Sid": "AllowS3ProjectAccess",
  "Effect": "Allow",
  "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetBucketLocation"],
  "Resource": ["arn:aws:s3:::${COMPANY}-sm-${TEAM}-${PROJECT}", "arn:aws:s3:::${COMPANY}-sm-${TEAM}-${PROJECT}/*"]
}

