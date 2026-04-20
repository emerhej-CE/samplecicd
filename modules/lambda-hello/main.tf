locals {
  name = "${var.project}-${var.environment}-hello"
}

data "archive_file" "zip" {
  type        = "zip"
  output_path = "${path.module}/.build/hello.zip"

  source {
    filename = "lambda.py"
    content  = <<-PY
      def lambda_handler(event, context):
          print("hello world")
          return {"statusCode": 200, "body": "hello world"}
      PY
  }
}

data "aws_iam_policy_document" "assume_lambda" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${local.name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda.json

  tags = merge(var.common_tags, { Name = "${local.name}-role" })
}

resource "aws_iam_role_policy_attachment" "basic" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "this" {
  function_name = local.name
  description   = "Minimal hello-world Lambda (logs + JSON body)."
  role          = aws_iam_role.this.arn
  handler       = "lambda.lambda_handler"
  runtime       = "python3.12"
  filename      = data.archive_file.zip.output_path
  package_type  = "Zip"

  source_code_hash = data.archive_file.zip.output_base64sha256

  tags = merge(var.common_tags, { Name = local.name })
}
