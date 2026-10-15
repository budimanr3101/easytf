// Generated catalog template inventory.
pub fn template(kind: &str) -> Option<&'static str> {
    match kind {
        "aws_acm_certificate" => Some(include_str!(
            "../templates/catalog/aws_acm_certificate/main.tf"
        )),
        "aws_acm_certificate_validation" => Some(include_str!(
            "../templates/catalog/aws_acm_certificate_validation/main.tf"
        )),
        "aws_cloudfront_distribution" => Some(include_str!(
            "../templates/catalog/aws_cloudfront_distribution/main.tf"
        )),
        "aws_cloudfront_origin_access_control" => Some(include_str!(
            "../templates/catalog/aws_cloudfront_origin_access_control/main.tf"
        )),
        "aws_cloudwatch_log_group" => Some(include_str!(
            "../templates/catalog/aws_cloudwatch_log_group/main.tf"
        )),
        "aws_cloudwatch_metric_alarm" => Some(include_str!(
            "../templates/catalog/aws_cloudwatch_metric_alarm/main.tf"
        )),
        "aws_db_instance" => Some(include_str!("../templates/catalog/aws_db_instance/main.tf")),
        "aws_db_parameter_group" => Some(include_str!(
            "../templates/catalog/aws_db_parameter_group/main.tf"
        )),
        "aws_db_subnet_group" => Some(include_str!(
            "../templates/catalog/aws_db_subnet_group/main.tf"
        )),
        "aws_ecr_lifecycle_policy" => Some(include_str!(
            "../templates/catalog/aws_ecr_lifecycle_policy/main.tf"
        )),
        "aws_ecr_repository" => Some(include_str!(
            "../templates/catalog/aws_ecr_repository/main.tf"
        )),
        "aws_eip" => Some(include_str!("../templates/catalog/aws_eip/main.tf")),
        "aws_eks_access_entry" => Some(include_str!(
            "../templates/catalog/aws_eks_access_entry/main.tf"
        )),
        "aws_eks_access_policy_association" => Some(include_str!(
            "../templates/catalog/aws_eks_access_policy_association/main.tf"
        )),
        "aws_eks_addon" => Some(include_str!("../templates/catalog/aws_eks_addon/main.tf")),
        "aws_eks_cluster" => Some(include_str!("../templates/catalog/aws_eks_cluster/main.tf")),
        "aws_eks_fargate_profile" => Some(include_str!(
            "../templates/catalog/aws_eks_fargate_profile/main.tf"
        )),
        "aws_eks_node_group" => Some(include_str!(
            "../templates/catalog/aws_eks_node_group/main.tf"
        )),
        "aws_iam_instance_profile" => Some(include_str!(
            "../templates/catalog/aws_iam_instance_profile/main.tf"
        )),
        "aws_iam_policy" => Some(include_str!("../templates/catalog/aws_iam_policy/main.tf")),
        "aws_iam_role" => Some(include_str!("../templates/catalog/aws_iam_role/main.tf")),
        "aws_iam_role_policy" => Some(include_str!(
            "../templates/catalog/aws_iam_role_policy/main.tf"
        )),
        "aws_iam_role_policy_attachment" => Some(include_str!(
            "../templates/catalog/aws_iam_role_policy_attachment/main.tf"
        )),
        "aws_internet_gateway" => Some(include_str!(
            "../templates/catalog/aws_internet_gateway/main.tf"
        )),
        "aws_nat_gateway" => Some(include_str!("../templates/catalog/aws_nat_gateway/main.tf")),
        "aws_rds_cluster" => Some(include_str!("../templates/catalog/aws_rds_cluster/main.tf")),
        "aws_rds_cluster_instance" => Some(include_str!(
            "../templates/catalog/aws_rds_cluster_instance/main.tf"
        )),
        "aws_rds_cluster_parameter_group" => Some(include_str!(
            "../templates/catalog/aws_rds_cluster_parameter_group/main.tf"
        )),
        "aws_route" => Some(include_str!("../templates/catalog/aws_route/main.tf")),
        "aws_route53_record" => Some(include_str!(
            "../templates/catalog/aws_route53_record/main.tf"
        )),
        "aws_route53_zone" => Some(include_str!(
            "../templates/catalog/aws_route53_zone/main.tf"
        )),
        "aws_route_table" => Some(include_str!("../templates/catalog/aws_route_table/main.tf")),
        "aws_route_table_association" => Some(include_str!(
            "../templates/catalog/aws_route_table_association/main.tf"
        )),
        "aws_s3_bucket" => Some(include_str!("../templates/catalog/aws_s3_bucket/main.tf")),
        "aws_s3_bucket_policy" => Some(include_str!(
            "../templates/catalog/aws_s3_bucket_policy/main.tf"
        )),
        "aws_s3_bucket_public_access_block" => Some(include_str!(
            "../templates/catalog/aws_s3_bucket_public_access_block/main.tf"
        )),
        "aws_s3_bucket_server_side_encryption_configuration" => Some(include_str!(
            "../templates/catalog/aws_s3_bucket_server_side_encryption_configuration/main.tf"
        )),
        "aws_s3_bucket_versioning" => Some(include_str!(
            "../templates/catalog/aws_s3_bucket_versioning/main.tf"
        )),
        "aws_security_group" => Some(include_str!(
            "../templates/catalog/aws_security_group/main.tf"
        )),
        "aws_subnet" => Some(include_str!("../templates/catalog/aws_subnet/main.tf")),
        "aws_vpc" => Some(include_str!("../templates/catalog/aws_vpc/main.tf")),
        "aws_vpc_security_group_egress_rule" => Some(include_str!(
            "../templates/catalog/aws_vpc_security_group_egress_rule/main.tf"
        )),
        "aws_vpc_security_group_ingress_rule" => Some(include_str!(
            "../templates/catalog/aws_vpc_security_group_ingress_rule/main.tf"
        )),
        _ => None,
    }
}
