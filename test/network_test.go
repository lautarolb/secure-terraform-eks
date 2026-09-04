package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

func TestNetworkModulePlan(t *testing.T) {
	t.Parallel()

	opts := &terraform.Options{
		TerraformDir: "../infra/modules/network",
		Vars: map[string]interface{}{
			"vpc_cidr": "10.0.0.0/16",
		},
		EnvVars: map[string]string{
			"AWS_PROFILE": "personal",
			"AWS_REGION":  "us-east-1",
		},
		PlanFilePath: "./network.tfplan",
		NoColor:      true,
	}

	planStruct := terraform.InitAndPlanAndShowWithStruct(t, opts)

	vpc := planStruct.ResourcePlannedValuesMap["aws_vpc.main"]
	assert.NotNil(t, vpc, "el plan deberia incluir aws_vpc.main")
	assert.Equal(t, "10.0.0.0/16", vpc.AttributeValues["cidr_block"])

	privateA := planStruct.ResourcePlannedValuesMap["aws_subnet.private_a"]
	assert.NotNil(t, privateA, "el plan deberia incluir aws_subnet.private_a")
	assert.Equal(t, "10.0.0.0/20", privateA.AttributeValues["cidr_block"])

	natGw := planStruct.ResourcePlannedValuesMap["aws_nat_gateway.main"]
	assert.NotNil(t, natGw, "el plan deberia incluir el NAT gateway")
}
