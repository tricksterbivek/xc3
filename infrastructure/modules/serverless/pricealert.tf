

locals {
  tags = {
    Owner   = var.owner_email
    Creator = var.creator_email
    Project = var.project
    Region = var.region
  }
}

data "archive_file" "price_alert" {
  type        = "zip"
  source_file = "../src/budget_details/pricealert.py"
  output_path = "${path.module}/pricealert.zip"
}

# Creating IAM Role for Lambda functions
resource "aws_iam_role" "price_alert" {
  name = "teamgxc-pricealert-role-j03nemht"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Sid    = "PriceAlert",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]
  tags                = merge(local.tags, tomap({ "Name" = "teamgxc-pricealert-role-j03nemht" }))
}

# Creating Inline policy for pricealert
resource "aws_iam_role_policy" "price_alert" {
  name = "teamgxc-pricealert-policy"
  role = aws_iam_role.price_alert.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "CostExplorerAccess",
        Effect    = "Allow",
        Action    = [
          "aws-portal:ViewBilling",
          "ce:GetCostAndUsage",
          "ec2:DescribeInstances",
          "ec2:DescribeRegions",
          "ses:SendEmail"
        ],
        Resource = "*"
      },
      {
        Effect    = "Allow",
        Action    = ["s3:PutObject"],
        Resource  = ["arn:aws:s3:::teamgxc-metadata-storage/*"]
      }
    ]
  })
}


resource "aws_lambda_function" "price_alert" {
  function_name = "${var.namespace}-${var.price_alert_lambda}"
  role          = aws_iam_role.price_alert.arn
  runtime       = "python3.9"
  handler       = "${var.price_alert_lambda}.lambda_handler"
  filename      = data.archive_file.price_alert.output_path
  environment {
    variables = {
      slack_webhook_url   = "https://hooks.slack.com/services/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",
      account_id          = var.account_id
    }
  }
  memory_size = var.memory_size
  timeout     = var.timeout
  vpc_config {
    subnet_ids         = [var.subnet_id[0]]
    security_group_ids = [var.security_group_id]
  }
  tags = merge(local.tags, tomap({ "Name" = "${var.namespace}-price-alert" }))
}

resource "terraform_data" "delete_zip_file_price_alert" {
  triggers_replace = [aws_lambda_function.price_alert.arn]
  provisioner "local-exec" {
    command = "rm -r ${data.archive_file.price_alert.output_path}"
  }
}

resource "aws_iam_policy" "price_alert" {
  name = "${var.namespace}-price_alert_eventbridge_policy"
  # [The policy details remain unchanged]
}

resource "aws_iam_role_policy_attachment" "price_alert" {
  policy_arn = aws_iam_policy.price_alert.arn
  role       = aws_iam_role.price_alert.name
}

resource "aws_cloudwatch_event_rule" "price_alert" {
  name                = "${var.namespace}-${var.price_alert_lambda}-rule"
  description         = "Trigger the Lambda function every two weeks"
  schedule_expression = var.price_alert_cronjob
  tags                = merge(local.tags, tomap({ "Name" = "${var.namespace}-price-alert-rule" }))
}

resource "aws_cloudwatch_event_target" "price_alert" {
  rule = aws_cloudwatch_event_rule.price_alert.name
  arn  = aws_lambda_function.price_alert.arn
}

resource "aws_lambda_permission" "price_alert" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.price_alert.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.price_alert.arn
}
