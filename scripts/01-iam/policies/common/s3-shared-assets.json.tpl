{
  "Sid": "AllowSharedAssetsReadOnly",
  "Effect": "Allow",
  "Action": ["s3:GetObject", "s3:ListBucket"],
  "Resource": ["arn:aws:s3:::${COMPANY}-sm-shared-assets", "arn:aws:s3:::${COMPANY}-sm-shared-assets/*"]
}

