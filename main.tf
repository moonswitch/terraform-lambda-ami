module "lambda_function" {
  source = "terraform-aws-modules/lambda/aws"

  function_name = "ami-patcher"
  description   = "lambda function for updating AMI"
  handler       = "index.handler"
  runtime       = "python3.8"

  source_path = "python"

  tags = {
    Name = "my-lambda1"
  }
}