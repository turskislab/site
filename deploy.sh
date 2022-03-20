#!/usr/bin/env bash
set -Eeuo pipefail


aws --version
jq --version
echo $AWS_ACCESS_KEY_ID

aws() {
  echo $@
}

jq() {
  echo $@
}


# run only if frontend artifact is avaiable
if [ -d "public" ]; then

  echo "push frontend"
  aws s3 sync                                \
    --delete public                          \
    "s3://codeforpoznan-public/${AWS_RESOURCE_NAME}"  \


  echo "refresh CDN"
  aws cloudfront create-invalidation         \
    --paths "/+"                             \
    --distribution-id "${AWS_CLOUDFRONT_ID}" \

else
  echo "no frontend artifact found, skipping..."
fi


# run only if backend artifact is avaiable
if [ -f "lambda.zip" ]; then

  echo "upload lambdas"
  aws s3 cp lambda.zip "s3://codeforpoznan-lambdas/${AWS_RESOURCE_NAME}_serverless_api.zip"
  aws s3 cp lambda.zip "s3://codeforpoznan-lambdas/${AWS_RESOURCE_NAME}_migration.zip"


  echo "refresh lambdas"
  aws lambda update-function-code                           \
    --s3-bucket     "codeforpoznan-lambdas"                 \
    --s3-key        "${AWS_RESOURCE_NAME}_serverless_api.zip"        \
    --function-name "${AWS_RESOURCE_NAME}_serverless_api"            \
  | jq 'del(.Environment, .VpcConfig, .Role, .FunctionArn)' \

  aws lambda update-function-code                           \
    --s3-bucket     "codeforpoznan-lambdas"                 \
    --s3-key        "${AWS_RESOURCE_NAME}_migration.zip"             \
    --function-name "${AWS_RESOURCE_NAME}_migration"                 \
  | jq 'del(.Environment, .VpcConfig, .Role, .FunctionArn)' \


  echo "run migrations"
  aws lambda invoke                         \
    --function-name "${uuuRESOURCE}_migration" \
    response.json                           \
  > request.json                            \


  echo "show migration output"
  jq -s add ./*.json | jq -re '
    if .FunctionError then
      .FunctionError, .errorMessage, false
    else
      .stdout, .stderr
    end'

else
  echo "no backend artifact found, skipping..."
fi


exit $?

