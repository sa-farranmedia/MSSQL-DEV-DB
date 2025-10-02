package test

import (
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestVPCAndEC2Infrastructure(t *testing.T) {
	t.Parallel()

	// Set region from environment or default
	region := os.Getenv("TEST_REGION")
	if region == "" {
		region = "us-east-2"
	}

	// Terraform options
	terraformOptions := &terraform.Options{
		TerraformDir: "../terraform",
		VarFiles:     []string{"envs/dev/dev.tfvars"},
		BackendConfig: map[string]interface{}{
			"bucket": "dev-sqlserver-supportfiles-backups-and-iso-files",
			"key":    "tfstate/dev/test-infra.tfstate",
			"region": region,
		},
		EnvVars: map[string]string{
			"AWS_DEFAULT_REGION": region,
		},
		MaxRetries:         3,
		TimeBetweenRetries: 5 * time.Second,
	}

	// Cleanup after test
	defer terraform.Destroy(t, terraformOptions)

	// Initialize and apply
	terraform.InitAndApply(t, terraformOptions)

	// Test 1: Verify backend is remote S3
	t.Run("BackendIsRemoteS3", func(t *testing.T) {
		// Check that terraform.tfstate is not present (remote backend)
		_, err := os.Stat("../terraform/terraform.tfstate")
		assert.True(t, os.IsNotExist(err), "Local terraform.tfstate should not exist with remote backend")
	})

	// Test 2: VPC and subnets
	t.Run("VPCConfiguration", func(t *testing.T) {
		vpcID := terraform.Output(t, terraformOptions, "vpc_id")
		vpcCIDR := terraform.Output(t, terraformOptions, "vpc_cidr")

		require.NotEmpty(t, vpcID)
		assert.Equal(t, "10.42.0.0/16", vpcCIDR)

		// Verify VPC exists in AWS
		vpc := aws.GetVpcById(t, vpcID, region)
		assert.Equal(t, "10.42.0.0/16", vpc.Cidr)
	})

	// Test 3: Subnet count and CIDRs
	t.Run("SubnetConfiguration", func(t *testing.T) {
		privateSubnets := terraform.OutputList(t, terraformOptions, "private_subnet_ids")
		publicSubnets := terraform.OutputList(t, terraformOptions, "public_subnet_ids")

		assert.Len(t, privateSubnets, 3, "Should have 3 private subnets")
		assert.Len(t, publicSubnets, 2, "Should have 2 public subnets")

		// Verify private subnet CIDRs
		expectedPrivateCIDRs := []string{"10.42.0.0/20", "10.42.16.0/20", "10.42.32.0/20"}
		for i, subnetID := range privateSubnets {
			subnet := aws.GetSubnetById(t, subnetID, region)
			assert.Contains(t, expectedPrivateCIDRs, subnet.Cidr)
			t.Logf("Private Subnet %d: %s (CIDR: %s)", i+1, subnetID, subnet.Cidr)
		}
	})

	// Test 4: VPC Endpoints
	t.Run("VPCEndpoints", func(t *testing.T) {
		if testing.Short() {
			t.Skip("Skipping VPC endpoint validation in short mode")
		}

		vpcID := terraform.Output(t, terraformOptions, "vpc_id")

		// Check Interface endpoints
		ssmEndpoint := terraform.Output(t, terraformOptions, "vpc_endpoint_ssm_id")
		ssmmessagesEndpoint := terraform.Output(t, terraformOptions, "vpc_endpoint_ssmmessages_id")
		ec2messagesEndpoint := terraform.Output(t, terraformOptions, "vpc_endpoint_ec2messages_id")
		logsEndpoint := terraform.Output(t, terraformOptions, "vpc_endpoint_logs_id")

		require.NotEmpty(t, ssmEndpoint, "SSM VPC endpoint should exist")
		require.NotEmpty(t, ssmmessagesEndpoint, "SSM Messages VPC endpoint should exist")
		require.NotEmpty(t, ec2messagesEndpoint, "EC2 Messages VPC endpoint should exist")
		require.NotEmpty(t, logsEndpoint, "CloudWatch Logs VPC endpoint should exist")

		// Check Gateway endpoint for S3
		s3Endpoint := terraform.Output(t, terraformOptions, "vpc_endpoint_s3_id")
		require.NotEmpty(t, s3Endpoint, "S3 Gateway VPC endpoint should exist")

		t.Logf("VPC Endpoints validated: SSM, SSMMessages, EC2Messages, Logs, S3")
	})

	// Test 5: EC2 Instance
	t.Run("EC2Instance", func(t *testing.T) {
		instanceID := terraform.Output(t, terraformOptions, "instance_id")
		require.NotEmpty(t, instanceID)

		// Verify instance type
		instance := aws.GetEc2InstanceById(t, instanceID, region)
		assert.Equal(t, "m6i.2xlarge", instance.InstanceType)
		t.Logf("EC2 Instance: %s (Type: %s)", instanceID, instance.InstanceType)

		// Verify no public IP
		assert.Empty(t, instance.PublicIpAddress, "Instance should not have a public IP")

		// Verify IMDSv2
		assert.Equal(t, "required", instance.MetadataOptions.HttpTokens)
		t.Logf("IMDSv2 is required: ✓")
	})

	// Test 6: Static Private IPs
	t.Run("StaticPrivateIPs", func(t *testing.T) {
		staticIPs := terraform.OutputList(t, terraformOptions, "static_private_ips")

		// Should have exactly 5 additional private IPs
		assert.Len(t, staticIPs, 5, "Should have exactly 5 static private IPs")

		// Verify IPs are within VPC CIDR
		for i, ip := range staticIPs {
			assert.True(t, strings.HasPrefix(ip, "10.42."),
				"IP %s should be within VPC CIDR 10.42.0.0/16", ip)
			t.Logf("Static IP %d: %s", i+1, ip)
		}
	})

	// Test 7: SSM Manageability
	t.Run("SSMManageability", func(t *testing.T) {
		if testing.Short() {
			t.Skip("Skipping SSM manageability check in short mode")
		}

		instanceID := terraform.Output(t, terraformOptions, "instance_id")

		// Wait for SSM agent to register (can take a few minutes)
		maxRetries := 30
		retryDelay := 10 * time.Second

		var isManaged bool
		for i := 0; i < maxRetries; i++ {
			isManaged = aws.IsInstanceManagedBySSM(t, instanceID, region)
			if isManaged {
				break
			}
			t.Logf("Waiting for SSM agent registration (attempt %d/%d)...", i+1, maxRetries)
			time.Sleep(retryDelay)
		}

		assert.True(t, isManaged, "Instance should be managed by SSM")
		t.Logf("Instance %s is SSM managed: ✓", instanceID)
	})

	// Test 8: RDS Custom Scheduler (if enabled)
	t.Run("RDSScheduler", func(t *testing.T) {
		if testing.Short() {
			t.Skip("Skipping RDS scheduler validation in short mode")
		}

		startRuleARN := terraform.Output(t, terraformOptions, "scheduler_start_rule_arn")
		stopRuleARN := terraform.Output(t, terraformOptions, "scheduler_stop_rule_arn")
		lambdaARN := terraform.Output(t, terraformOptions, "scheduler_lambda_arn")

		// These should be non-empty if scheduler is enabled
		if startRuleARN != "" {
			require.NotEmpty(t, stopRuleARN, "Stop rule should exist")
			require.NotEmpty(t, lambdaARN, "Lambda function should exist")

			t.Logf("Scheduler enabled:")
			t.Logf("  Start Rule: %s", startRuleARN)
			t.Logf("  Stop Rule: %s", stopRuleARN)
			t.Logf("  Lambda: %s", lambdaARN)
		} else {
			t.Log("Scheduler not enabled, skipping validation")
		}
	})

	// Test 9: Security Groups
	t.Run("SecurityGroups", func(t *testing.T) {
		instanceID := terraform.Output(t, terraformOptions, "instance_id")
		instance := aws.GetEc2InstanceById(t, instanceID, region)

		// Verify security groups are attached
		assert.NotEmpty(t, instance.SecurityGroupIds, "Instance should have security groups")
		t.Logf("Security Groups: %v", instance.SecurityGroupIds)
	})

	// Test 10: Outputs Validation
	t.Run("OutputsValidation", func(t *testing.T) {
		// Verify all critical outputs are present
		vpcID := terraform.Output(t, terraformOptions, "vpc_id")
		instanceID := terraform.Output(t, terraformOptions, "instance_id")
		primaryENI := terraform.Output(t, terraformOptions, "primary_eni_id")
		ssmCommand := terraform.Output(t, terraformOptions, "ssm_connect_command")

		require.NotEmpty(t, vpcID, "VPC ID output should be present")
		require.NotEmpty(t, instanceID, "Instance ID output should be present")
		require.NotEmpty(t, primaryENI, "Primary ENI ID output should be present")
		require.NotEmpty(t, ssmCommand, "SSM connect command should be present")

		// Verify SSM command format
		expectedCommand := fmt.Sprintf("aws ssm start-session --target %s --region %s", instanceID, region)
		assert.Equal(t, expectedCommand, ssmCommand, "SSM command should be correctly formatted")

		t.Logf("All outputs validated successfully")
	})
}

func TestBackendConfiguration(t *testing.T) {
	t.Run("ValidateS3Backend", func(t *testing.T) {
		region := os.Getenv("TEST_REGION")
		if region == "" {
			region = "us-east-2"
		}

		bucketName := "dev-sqlserver-supportfiles-backups-and-iso-files"

		// Verify bucket exists and is accessible
		aws.AssertS3BucketExists(t, region, bucketName)

		t.Logf("S3 backend bucket validated: %s", bucketName)
	})
}
