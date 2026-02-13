#!/usr/bin/env bash
# AWS CLI utilities and functions

function aws-ip() {
  echo "$1" | sed 's/-/./g' | pbcopy
}

aws_ecr_login() {
  local region="${1:-us-east-1}"
  local account_id
  account_id=$(aws sts get-caller-identity --query Account --output text)
  aws ecr get-login-password --region "$region" | \
    docker login --username AWS --password-stdin "${account_id}.dkr.ecr.${region}.amazonaws.com"
}

aws_all_instances() {
  if [[ -n "$1" ]]; then
    for i in $(aws ec2 describe-regions --profile $1 | grep RegionName | cut -d'"' -f4); do
      echo -e "$i\n"
      aws ec2 describe-instances --region $i --profile $1
    done
  fi
}

aws_all_regions() {
  if [[ -n "$1" ]]; then
    aws ec2 describe-regions --profile $1
  fi
}

aws_all_availability_zones() {
  if [[ -n "$1" ]]; then
    for i in $(aws ec2 describe-regions --profile $1 | grep RegionName | cut -d'"' -f4); do
      echo -e "$i\n"
      aws ec2 describe-availability-zones --region $i --profile $1 | grep ZoneName
    done
  fi
}

aws_ami_ids() {
  if [[ -n "$1" ]]; then
    aws --profile $1 ec2 describe-images --filters 'Name=owner-alias,Values=amazon' 'Name=architecture,Values=x86_64' 'Name=root-device-type,Values=ebs'
  fi
}

aws_instances_amis() {
  # This requires jq1.5
  aws ec2 describe-instances | jq -r '.Reservations[].Instances[]| [{ "Key": .ImageId, "Value": (.Tags|from_entries|.Version) }] | from_entries'
}

instances-windows() {
  aws ec2 describe-instances --query "Reservations[?contains(Instances[].Platform, \`windows\`)].Instances[].[InstanceId]" --output text
}

aws-regions() {
  aws ec2 describe-regions --query 'Regions[].{Name:RegionName}' --output text
}

aws-kms-encrypt() {
  local sourcefile=$1
  local destinationfile=$2
  local keyid=$3
  aws kms encrypt --key-id "${keyid}" --plaintext fileb://${sourcefile} --query CiphertextBlob --output text | base64 -D | base64 -b 76 | pbcopy
}

aws-kms-decrypt() {
  local sourcefile=$1
  local destinationfile=$2
  aws kms decrypt --ciphertext-blob fileb://<(cat ${sourcefile} | base64 -D) --output text --query Plaintext | base64 -D > ${destinationfile}
}

aws-validate-template() {
  IFS=''
  local template=$1
  aws cloudformation validate-template --template-body file://${template}
}

aws-create-stack() {
  local stackname=$1
  local template=$2
  local parameters=$3
  aws cloudformation create-stack --stack-name ${stackname} --template-body file:///${template} --parameters file:///${parameters} --capabilities CAPABILITY_IAM
}

aws-update-stack() {
  local stackname=$1
  local template=$2
  local parameters=$3
  aws cloudformation update-stack --stack-name ${stackname} --template-body file:///${template} --parameters file:///${parameters} --capabilities CAPABILITY_IAM
}

aws-canonical-id() {
  aws s3api list-buckets | jq -r '.Owner.ID'
}

function aws_list_all_ec2_instances_in_all_regions() {
  for region in $(aws ec2 describe-regions --output text | cut -f3); do
    echo -e "\nListing Instances in region:'$region'..."
    aws ec2 describe-instances --region $region | jq '.Reservations[] | ( .Instances[] | {state: .State.Name, name: .KeyName, type: .InstanceType, key: .KeyName})'
  done
}

function aws_assume_role_creds() {
  local ROLE_ARN="$1"
  "${ROLE_ARN:?You must set ROLE_ARN}"

  aws sts assume-role \
    --region ap-southeast-2 \
    --role-arn ${ROLE_ARN} \
    --role-session-name $(whoami)'-'$(date +%s) \
    | jq -r ".Credentials|to_entries|map(\"\(.key)=\(.value|tostring)\")|.[]" \
    | sed -e 's|AccessKeyId|aws_access_key_id|' \
      -e 's|SecretAccessKey|aws_secret_access_key|' \
      -e 's|SessionToken|aws_session_token|' \
      -e 's|Expiration|aws_session_expiration|'
}

