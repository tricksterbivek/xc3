locals {
  tag_name = {
    Owner   = var.owner_email
    Creator = var.creator_email
    Project = var.namespace
  }
}

data "archive_file" "most_expensive_service_archive" {
  type        = "zip"
  source_file = "../lambda_functions/expensive_services_detail/most_expensive_service.py"
  output_path = "${path.module}/most_expensive_service.zip"
}

# Creating IAM Role for Lambda functions
resource "aws_iam_role" "most_expensive_service_role" {
  name = "${var.namespace}-most_expensive_service_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = "TotalAccountCost"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]
  tags                = merge(local.tag_name, tomap({ "Name" = "${local.tag_name.Project}-most_expensive_service_role"}))

}

# Creating Inline policy
resource "aws_iam_role_policy" "most_expensive_service_policy" {
  name = "${var.namespace}-most_expensive_service_policy"
  role = aws_iam_role.most_expensive_service_role.id
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "TotalAccountCost",
        "Effect" : "Allow",
        "Action" : [
          "ce:GetCostAndUsage",
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DetachNetworkInterface",
          "ec2:AttachNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeRegions"
        ]
        "Resource" : "*"
      }
    ]
  })
}

resource "aws_lambda_function" "most_expensive_service" {
  function_name = "${var.namespace}-most_expensive_service_lambda"
  role          = aws_iam_role.most_expensive_service_role.arn
  runtime       = "python3.9"
  handler       = "most_expensive_service.lambda_handler"
  filename      = data.archive_file.most_expensive_service_archive.output_path
  environment {
    variables = {
      prometheus_ip = "${var.prometheus_ip}:9091"
    }
  }
  memory_size = var.memory_size
  timeout     = var.timeout
  layers      = [var.prometheus_layer]
  vpc_config {
    subnet_ids         = [var.subnet_id]
    security_group_ids = [var.security_group_id]
  }
  tags = merge(local.tag_name, tomap({ "Name" = "${local.tag_name.Project}-most_expensive_service" }))

}

resource "null_resource" "delete_lambda_zip_file" {
  triggers = {
    lambda_function_arn = aws_lambda_function.most_expensive_service.arn
  }
  provisioner "local-exec" {
    command = "rm -r ${data.archive_file.most_expensive_service_archive.output_path}"
  }
}
