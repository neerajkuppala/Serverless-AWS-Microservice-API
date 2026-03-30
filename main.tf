resource "aws_s3_bucket" "my_bucket" {
  bucket         = "neeraj-serverless-project-2026" # Your new name!
  force_destroy  = true # This allows Terraform to delete the old non-empty bucket
}
resource "aws_iam_role" "lambda_role" {
  name = "microservice_lambda_role_v2"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}
resource "aws_iam_role_policy" "s3_access" {
  name = "lambda_s3_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Effect   = "Allow"
        Resource = [
          "arn:aws:s3:::neeraj-serverless-project-2026",
          "arn:aws:s3:::neeraj-serverless-project-2026/*"
        ]
      }
    ]
  })
}
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "functions/api_handler.py"
  output_path = "lambda_function_payload.zip"
}
resource "aws_lambda_function" "my_microservice" {
  filename      = "lambda_function_payload.zip"
  function_name = "NeerajMicroserviceAPI"
  role          = aws_iam_role.lambda_role.arn
  handler       = "api_handler.lambda_handler"
  runtime       = "python3.11"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
}
resource "aws_apigatewayv2_api" "lambda_api" {
  name          = "NeerajMicroserviceGateway"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "lambda_stage" {
  api_id      = aws_apigatewayv2_api.lambda_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.lambda_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.my_microservice.invoke_arn
}

resource "aws_apigatewayv2_route" "lambda_route" {
  api_id    = aws_apigatewayv2_api.lambda_api.id
  route_key = "GET /hello"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.my_microservice.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.lambda_api.execution_arn}/*/*"
}


output "base_url" {
  value = "${aws_apigatewayv2_api.lambda_api.api_endpoint}/hello"
}
resource "aws_dynamodb_table" "project_db" {
  name           = "UserUploads"
  billing_mode   = "PAY_PER_REQUEST" # Perfect for beginners: no cost if not used
  hash_key       = "UserId"

  attribute {
    name = "UserId"
    type = "S" # 'S' means String
  }
}
resource "aws_iam_role_policy" "dynamo_policy" {
  name = "lambda_dynamo_policy"
  role = aws_iam_role.lambda_role.id 

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["dynamodb:PutItem", "dynamodb:GetItem"]
      Effect   = "Allow"
      Resource = "${aws_dynamodb_table.project_db.arn}"
    }]
  })
}
resource "aws_cognito_user_pool" "pool" {
  name = "project_user_pool"
}

resource "aws_cognito_user_pool_client" "client" {
  name         = "my-app-client"
  user_pool_id = aws_cognito_user_pool.pool.id # This links it to your 'pool'
}
resource "aws_apigatewayv2_authorizer" "auth" {
  api_id           = aws_apigatewayv2_api.lambda_api.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "cognito-authorizer"
  
  jwt_configuration {
    audience = [aws_cognito_user_pool_client.client.id] 
    issuer   = "https://${aws_cognito_user_pool.pool.endpoint}"
  }
}