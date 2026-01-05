{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowProcessingOperations",
      "Effect": "Allow",
      "Action": ["sagemaker:CreateProcessingJob", "sagemaker:DescribeProcessingJob", "sagemaker:StopProcessingJob", "sagemaker:ListProcessingJobs", "sagemaker:AddTags", "sagemaker:ListTags"],
      "Resource": ["arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:processing-job/${TEAM}-${PROJECT}-*"]
    },
    {
      "Sid": "AllowDataWranglerOperations",
      "Effect": "Allow",
      "Action": ["sagemaker:CreateDataQualityJobDefinition", "sagemaker:DescribeDataQualityJobDefinition", "sagemaker:DeleteDataQualityJobDefinition", "sagemaker:ListDataQualityJobDefinitions"],
      "Resource": ["arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:data-quality-job-definition/${TEAM}-${PROJECT}-*"]
    },
    {
      "Sid": "AllowFeatureStoreAccess",
      "Effect": "Allow",
      "Action": ["sagemaker:CreateFeatureGroup", "sagemaker:DescribeFeatureGroup", "sagemaker:UpdateFeatureGroup", "sagemaker:DeleteFeatureGroup", "sagemaker:ListFeatureGroups", "sagemaker:PutRecord", "sagemaker:GetRecord", "sagemaker:DeleteRecord", "sagemaker:BatchGetRecord"],
      "Resource": ["arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:feature-group/${TEAM}-${PROJECT}-*"]
    },
    {
      "Sid": "AllowGlueForDataWrangler",
      "Effect": "Allow",
      "Action": ["glue:GetDatabase", "glue:GetDatabases", "glue:GetTable", "glue:GetTables", "glue:GetPartition", "glue:GetPartitions", "glue:BatchGetPartition"],
      "Resource": ["arn:aws:glue:${AWS_REGION}:${AWS_ACCOUNT_ID}:catalog", "arn:aws:glue:${AWS_REGION}:${AWS_ACCOUNT_ID}:database/*", "arn:aws:glue:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/*/*"]
    },
    {
      "Sid": "AllowAthenaForDataWrangler",
      "Effect": "Allow",
      "Action": ["athena:StartQueryExecution", "athena:GetQueryExecution", "athena:GetQueryResults", "athena:StopQueryExecution"],
      "Resource": ["arn:aws:athena:${AWS_REGION}:${AWS_ACCOUNT_ID}:workgroup/primary"]
    },
    {
      "Sid": "AllowPassRoleToSageMaker",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/SageMaker-${TEAM_FULLNAME}-${PROJECT_FULLNAME}-ProcessingRole",
      "Condition": {"StringEquals": {"iam:PassedToService": "sagemaker.amazonaws.com"}}
    },
    {
      "Sid": "AllowKMSForProcessing",
      "Effect": "Allow",
      "Action": ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey"],
      "Resource": "arn:aws:kms:${AWS_REGION}:${AWS_ACCOUNT_ID}:key/*",
      "Condition": {"StringLike": {"kms:ViaService": "sagemaker.${AWS_REGION}.amazonaws.com"}}
    }
  ]
}

