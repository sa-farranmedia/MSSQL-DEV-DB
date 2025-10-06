REGION=us-east-2
read -rp "Enter EC2 INSTANCE ID (e.g., i-0123456789abcdef0): " INSTANCE_ID
if [[ -z "${INSTANCE_ID}" ]]; then
  echo "ERROR: INSTANCE ID is required"; exit 1
fi
SUBNET_ID=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].SubnetId' --output text)

VPC_ID=$(aws ec2 describe-subnets --region "$REGION" --subnet-ids "$SUBNET_ID" \
  --query 'Subnets[0].VpcId' --output text)

# Prefer explicit association; else use the VPC’s main route table
RTB_ID=$(aws ec2 describe-route-tables --region "$REGION" \
  --filters Name=association.subnet-id,Values="$SUBNET_ID" \
  --query 'RouteTables[0].RouteTableId' --output text)

if [[ -z "$RTB_ID" || "$RTB_ID" == "None" || "$RTB_ID" == "null" ]]; then
  RTB_ID=$(aws ec2 describe-route-tables --region "$REGION" \
    --filters Name=vpc-id,Values="$VPC_ID" Name=association.main,Values=true \
    --query 'RouteTables[0].RouteTableId' --output text)
fi

echo "VPC_ID=$VPC_ID  RTB_ID=$RTB_ID"
[[ -z "$RTB_ID" || "$RTB_ID" == "None" || "$RTB_ID" == "null" ]] && { echo "no route table found; stop."; exit 1; }

# Create or reuse the S3 Gateway endpoint in THIS VPC and attach THIS RTB
S3_EP_ID=$(aws ec2 describe-vpc-endpoints --region "$REGION" \
  --filters Name=vpc-id,Values="$VPC_ID" Name=vpc-endpoint-type,Values=Gateway \
           Name=service-name,Values=com.amazonaws.$REGION.s3 \
  --query 'VpcEndpoints[0].VpcEndpointId' --output text)

if [[ -z "$S3_EP_ID" || "$S3_EP_ID" == "None" || "$S3_EP_ID" == "null" ]]; then
  S3_EP_ID=$(aws ec2 create-vpc-endpoint --region "$REGION" \
    --vpc-id "$VPC_ID" \
    --vpc-endpoint-type Gateway \
    --service-name com.amazonaws.$REGION.s3 \
    --route-table-ids "$RTB_ID" \
    --query 'VpcEndpoint.VpcEndpointId' --output text)
else
  aws ec2 modify-vpc-endpoint --region "$REGION" \
    --vpc-endpoint-id "$S3_EP_ID" --add-route-table-ids "$RTB_ID"
fi

# Verify: should show a route with DestinationPrefixListId (pl-...)
aws ec2 describe-route-tables --region "$REGION" --route-table-ids "$RTB_ID" \
  --query 'RouteTables[0].Routes[?DestinationPrefixListId!=null]'