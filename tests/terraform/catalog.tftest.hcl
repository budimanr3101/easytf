mock_provider "aws" {}
run "catalog_plan_without_live_aws" {
  command = plan
  assert {
    condition = var.managed_resources.db_instance.configuration.manage_master_user_password && var.managed_resources.rds_cluster.configuration.manage_master_user_password
    error_message = "Database defaults must keep master password management with AWS."
  }
  assert {
    condition = length(var.managed_resources.eks_node_group.links["/subnet_ids"]) == 2 && length(var.managed_resources.eks_fargate_profile.links["/subnet_ids"]) == 1
    error_message = "Both EKS compute modes must retain their subnet references."
  }
}
