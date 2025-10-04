package test

import (
	"fmt"
	"os"
	"testing"

	"github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestVPCAndEC2Infrastructure(t *testing.T) {
	t.Parallel()

	// AWS region
	awsRegion := "us-east-2"

	// Terraform options
	terraformOptions := &terraform.Options{
		TerraformDir: "../terraform",
		VarFiles:     []string{"envs/dev/dev.tfvars"},
		BackendConfig: map[string]interface{}{
			"bucket": "dev-sqlserver-supportfiles-backups-and-iso-files",
			"key":    "tfstate/dev/infra-test.tfstate",
			"region": awsRegion,
		},
		EnvVars: map[string]string{
			"AWS_DEFAULT_REGION": awsRegion,
		},
	}

	// Cleanup after test
	defer terraform.Destroy(t, terraformOptions)

	// Initialize and apply Terraform
	terraform.InitAndApply(t, terraformOptions)

	// Run assertions
	t.Run("VPC Configuration", func(t *testing.T) {
		testVPCConfiguration(t, terraformOptions, awsRegion)
	})

	t.Run("VPC Endpoints", func(t *testing.T) {
		testVPCEndpoints(t, terraformOptions, awsRegion)
	})

	t.Run("EC2 Instance", func(t *testing.T) {
		testEC2Instance(t, terraformOptions, awsRegion)
	})

	t.Run("EC2 IMDSv2", func(t *testing.T) {
		testEC2IMDSv2(t, terraformOptions, awsRegion)
	})

	t.Run("EC2 Private IPs", func(t *testing.T) {
		testEC2PrivateIPs(t, terraformOptions, awsRegion)
	})

	t.Run("SSM Managed Instance", func(t *testing.T) {
		testSSMManagedInstance(t, terraformOptions, awsRegion)
	})

	t.Run("Remote S3 Backend", func(t *testing.T) {
		testRemoteBackend(t, terraformOptions)
	})
}

func testVPCConfiguration(t *testing.T, opts *terraform.Options, region string) {
	// Get VPC outputs
	vpcID := terraform.Output(t, opts, "vpc_id")
	vpcCIDR := terraform.Output(t, opts, "vpc_cidr")
	privateSubnetIDs := terraform.OutputList(t, opts, "private_subnet_ids")
	publicSubnetIDs := terraform.OutputList(t, opts, "public_subnet_ids")

	// Assert VPC CIDR
	assert.Equal(t, "10.42.0.0/16", vpcCIDR, "VPC CIDR should be 10.42.0.0/16")

	// Assert subnet counts
	assert.Equal(t, 3, len(privateSubnetIDs), "Should have 3 private subnets")
	assert.Equal(t, 2, len(publicSubnetIDs), "Should have 2 public subnets")

	// Get VPC details from AWS
	vpc := aws.GetVpcById(t, vpcID, region)
	assert.Equal(t, vpcCIDR, vpc.CIDR, "VPC CIDR in AWS should match output")

	// Verify specific subnet CIDRs
	expectedPrivateCIDRs := []string{"10.42.0.0/20", "10.42.16.0/20", "10.42.32.0/20"}
	expectedPublicCIDRs := []string{"10.42.240.0/24", "10.42.241.0/24"}

	for i, subnetID := range privateSubnetIDs {
		subnet := aws.GetSubnetById(t, subnetID, region)
		assert.Equal(t, expectedPrivateCIDRs[i], subnet.CIDR,
			fmt.Sprintf("Private subnet %d CIDR should be %s", i+1, expectedPrivateCIDRs[i]))
	}

	for i, subnetID := range publicSubnetIDs {
		subnet := aws.GetSubnetById(t, subnetID, region)
		assert.Equal(t, expectedPublicCIDRs[i], subnet.CIDR,
			fmt.Sprintf("Public subnet %d CIDR should be %s", i+1, expectedPublicCIDRs[i]))
	}

	t.Log("✓ VPC configuration verified")
}

func testVPCEndpoints(t *testing.T, opts *terraform.Options, region string) {
	// Required VPC endpoint service names
	requiredEndpoints := map[string]string{
		"ssm":          "com.amazonaws.us-east-2.ssm",
		"ssmmessages":  "com.amazonaws.us-east-2.ssmmessages",
		"ec2messages":  "com.amazonaws.us-east-2.ec2messages",
		"logs":         "com.amazonaws.us-east-2.logs",
	}

	// Get VPC ID
	vpcID := terraform.Output(t, opts, "vpc_id")

	// Get all VPC endpoints in the VPC
	endpoints := aws.GetVpcEndpointsForService(t, region, vpcID)

	// Verify each required endpoint exists
	for name, serviceName := range requiredEndpoints {
		found := false
		for _, endpoint := range endpoints {
			if endpoint.ServiceName == serviceName {
				found = true
				assert.Equal(t, "Interface", endpoint.VpcEndpointType,
					fmt.Sprintf("%s endpoint should be Interface type", name))
				break
			}
		}
		assert.True(t, found, fmt.Sprintf("VPC endpoint for %s (%s) should exist", name, serviceName))
	}

	// Verify S3 gateway endpoint exists
	s3Endpoints := aws.GetVpcEndpointsForService(t, region, vpcID)
	s3Found := false
	for _, endpoint := range s3Endpoints {
		if endpoint.ServiceName == "com.amazonaws.us-east-2.s3" {
			s3Found = true
			assert.Equal(t, "Gateway", endpoint.VpcEndpointType, "S3 endpoint should be Gateway type")
			break
		}
	}
	assert.True(t, s3Found, "S3 gateway VPC endpoint should exist")

	t.Log("✓ All required VPC endpoints verified")
}

func testEC2Instance(t *testing.T, opts *terraform.Options, region string) {
	// Get instance ID
	instanceID := terraform.Output(t, opts, "ec2_instance_id")
	require.NotEmpty(t, instanceID, "EC2 instance ID should not be empty")

	// Get instance details from AWS
	instance := aws.GetEc2InstanceById(t, instanceID, region)

	// Assert instance type
	assert.Equal(t, "m6i.2xlarge", instance.InstanceType, "Instance type should be m6i.2xlarge")

	// Assert no public IP
	assert.Empty(t, instance.PublicIpAddress, "Instance should not have a public IP address")

	// Assert instance is in private subnet
	privateSubnetIDs := terraform.OutputList(t, opts, "private_subnet_ids")
	assert.Contains(t, privateSubnetIDs, instance.SubnetId,
		"Instance should be in one of the private subnets")

	// Assert instance is running
	assert.Equal(t, "running", instance.State, "Instance should be in running state")

	t.Log("✓ EC2 instance configuration verified")
}

func testEC2IMDSv2(t *testing.T, opts *terraform.Options, region string) {
	// Get instance ID
	instanceID := terraform.Output(t, opts, "ec2_instance_id")

	// Get instance metadata options
	instance := aws.GetEc2InstanceById(t, instanceID, region)

	// Assert IMDSv2 is required
	assert.Equal(t, "required", instance.MetadataOptions.HttpTokens,
		"IMDSv2 should be required (http_tokens='required')")

	assert.Equal(t, "enabled", instance.MetadataOptions.HttpEndpoint,
		"Metadata endpoint should be enabled")

	t.Log("✓ IMDSv2 verified as required")
}

func testEC2PrivateIPs(t *testing.T, opts *terraform.Options, region string) {
	// Get instance ID
	instanceID := terraform.Output(t, opts, "ec2_instance_id")

	// Get all private IPs from output
	allPrivateIPs := terraform.OutputList(t, opts, "ec2_all_private_ips")

	// Should have exactly 6 IPs (1 primary + 5 secondary)
	require.Equal(t, 6, len(allPrivateIPs),
		"EC2 should have exactly 6 private IPs (1 primary + 5 secondary)")

	// Get instance from AWS
	instance := aws.GetEc2InstanceById(t, instanceID, region)

	// Verify instance has exactly one network interface (primary ENI)
	require.Equal(t, 1, len(instance.NetworkInterfaces),
		"Instance should have exactly 1 network interface (no multi-ENI)")

	primaryENI := instance.NetworkInterfaces[0]

	// Verify primary ENI has 6 private IPs
	assert.Equal(t, 6, len(primaryENI.PrivateIpAddresses),
		"Primary ENI should have 6 private IP addresses")

	// Verify expected IPs are assigned
	expectedIPs := []string{
		"10.42.0.60", "10.42.0.61", "10.42.0.62",
		"10.42.0.63", "10.42.0.64", "10.42.0.65",
	}

	actualIPs := make([]string, 0)
	for _, ipInfo := range primaryENI.PrivateIpAddresses {
		actualIPs = append(actualIPs, ipInfo.PrivateIpAddress)
	}

	for _, expectedIP := range expectedIPs {
		assert.Contains(t, actualIPs, expectedIP,
			fmt.Sprintf("Expected IP %s should be assigned to primary ENI", expectedIP))
	}

	t.Log("✓ EC2 private IP configuration verified (6 IPs on primary ENI)")
}

func testSSMManagedInstance(t *testing.T, opts *terraform.Options, region string) {
	// Get instance ID
	instanceID := terraform.Output(t, opts, "ec2_instance_id")

	// Check if instance is SSM-managed
	// Note: This requires the instance to have SSM agent running and properly configured
	// In a real test, you might need to wait for the instance to register with SSM

	instance := aws.GetEc2InstanceById(t, instanceID, region)

	// Verify instance has IAM instance profile attached
	assert.NotNil(t, instance.IamInstanceProfile,
		"Instance should have an IAM instance profile attached")

	// Verify IAM profile name contains expected pattern
	assert.Contains(t, instance.IamInstanceProfile.Arn, "ec2-profile",
		"IAM instance profile should be for EC2")

	t.Log("✓ EC2 instance has SSM IAM role attached")
}

func testRemoteBackend(t *testing.T, opts *terraform.Options) {
	// Check that terraform.tfstate does NOT exist locally
	_, err := os.Stat("../terraform/terraform.tfstate")
	assert.True(t, os.IsNotExist(err),
		"Local terraform.tfstate should not exist (using remote S3 backend)")

	// Verify backend configuration is present
	_, err = os.Stat("../terraform/backend.tf")
	assert.False(t, os.IsNotExist(err),
		"backend.tf should exist")

	t.Log("✓ Remote S3 backend verified (no local state file)")
}


