{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyUnauthorizedInstanceTypes",
      "Effect": "Deny",
      "Action": [
        "sagemaker:CreateApp"
      ],
      "Resource": "*",
      "Condition": {
        "StringNotEqualsIfExists": {
          "sagemaker:InstanceTypes": ${ALLOWED_INSTANCE_TYPES}
        }
      }
    }
  ]
}

