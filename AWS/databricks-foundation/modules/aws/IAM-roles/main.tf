locals {
  databricks_pass_compute_instance_profile_statement = {
    Sid      = "DatabricksPassComputeInstanceProfile"
    Effect   = "Allow"
    Action   = "iam:PassRole"
    Resource = aws_iam_role.workspace_instance_profile.arn
    Condition = {
      StringEquals = { "iam:PassedToService" = "ec2.amazonaws.com" }
    }
  }

  databricks_cross_account_assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowDatabricksControlPlane"
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { AWS = "arn:${var.aws_partition}:iam::${var.databricks_control_plane_account_id}:root" }
      Condition = { StringEquals = { "sts:ExternalId" = var.databricks_account_id } }
    }]
  })

  databricks_cross_account_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DatabricksCustomerManagedVpcCompute"
        Effect = "Allow"
        Action = [
          "ec2:AssociateIamInstanceProfile",
          "ec2:AttachVolume",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:CancelSpotInstanceRequests",
          "ec2:CreateFleet",
          "ec2:CreateLaunchTemplate",
          "ec2:CreateLaunchTemplateVersion",
          "ec2:CreateTags",
          "ec2:CreateVolume",
          "ec2:DeleteFleets",
          "ec2:DeleteLaunchTemplate",
          "ec2:DeleteLaunchTemplateVersions",
          "ec2:DeleteTags",
          "ec2:DeleteVolume",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeFleetHistory",
          "ec2:DescribeFleetInstances",
          "ec2:DescribeFleets",
          "ec2:DescribeIamInstanceProfileAssociations",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeInstances",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:DescribeNatGateways",
          "ec2:DescribeNetworkAcls",
          "ec2:DescribePrefixLists",
          "ec2:DescribeReservedInstancesOfferings",
          "ec2:DescribeRouteTables",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSpotInstanceRequests",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeSubnets",
          "ec2:DescribeVolumes",
          "ec2:DescribeVpcAttribute",
          "ec2:DescribeVpcs",
          "ec2:DetachVolume",
          "ec2:DisassociateIamInstanceProfile",
          "ec2:GetLaunchTemplateData",
          "ec2:ModifyFleet",
          "ec2:ModifyLaunchTemplate",
          "ec2:ReplaceIamInstanceProfileAssociation",
          "ec2:RequestSpotInstances",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:RunInstances",
          "ec2:TerminateInstances",
        ]
        Resource = "*"
      },
      {
        Sid      = "DatabricksSpotServiceLinkedRole"
        Effect   = "Allow"
        Action   = ["iam:CreateServiceLinkedRole", "iam:PutRolePolicy"]
        Resource = "arn:${var.aws_partition}:iam::*:role/aws-service-role/spot.amazonaws.com/AWSServiceRoleForEC2Spot"
        Condition = {
          StringLike = { "iam:AWSServiceName" = "spot.amazonaws.com" }
        }
      },
      local.databricks_pass_compute_instance_profile_statement,
    ]
  })

  ec2_assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEc2Instances"
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role" "databricks_cross_account" {
  name                 = "${var.name}-cross-account"
  assume_role_policy   = local.databricks_cross_account_assume_role_policy
  permissions_boundary = var.permissions_boundary_arn

  tags = merge(var.tags, {
    Name = "${var.name}-cross-account"
  })
}

resource "aws_iam_policy" "databricks_cross_account" {
  name        = "${var.name}-cross-account"
  description = "Databricks customer-managed VPC workspace deployment permissions"
  policy      = local.databricks_cross_account_policy

  tags = merge(var.tags, {
    Name = "${var.name}-cross-account"
  })
}

resource "aws_iam_role_policy_attachment" "databricks_cross_account" {
  role       = aws_iam_role.databricks_cross_account.name
  policy_arn = aws_iam_policy.databricks_cross_account.arn
}

resource "aws_iam_role" "workspace_instance_profile" {
  name                 = "${var.name}-instance-profile"
  assume_role_policy   = local.ec2_assume_role_policy
  permissions_boundary = var.permissions_boundary_arn

  tags = merge(var.tags, {
    Name = "${var.name}-instance-profile"
  })
}

resource "aws_iam_instance_profile" "workspace" {
  name = "${var.name}-instance-profile"
  role = aws_iam_role.workspace_instance_profile.name

  tags = merge(var.tags, {
    Name = "${var.name}-instance-profile"
  })
}
