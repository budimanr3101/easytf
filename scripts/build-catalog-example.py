#!/usr/bin/env python3
"""Offline placeholder fixture covering the complete catalog and cross-resource references."""
import json
from pathlib import Path
catalog=json.loads(Path('schemas/resource-catalog.json').read_text())['resources']
def required(node,name):
 kind=node['kind']
 if kind=='object':return {k:required(v,k) for k,v in node.get('properties',{}).items() if v.get('required')}
 if kind=='list':return [required(node['element'],name)]
 if kind=='map':return {}
 if kind=='bool':return False
 if kind=='number':return 1
 return 'sample-'+name.replace('_','-')
resources={}
for kind,d in catalog.items():
 key=kind.removeprefix('aws_'); config=required(d['schema'],key);config.update(d['defaults'])
 resources[key]={'kind':kind,'configuration':config,'links':{},'depends_on':[],'tags':{}}
def update(key,**fields):resources[key]['configuration'].update(fields)
def link(key,pointer,target,output='id'):
 resources[key]['links'].setdefault(pointer,[]).append({'resource_key':target,'output':output})
def policy(service):return json.dumps({'Version':'2012-10-17','Statement':[{'Effect':'Allow','Principal':{'Service':service},'Action':'sts:AssumeRole'}]})
update('vpc',cidr_block='10.60.0.0/16')
update('subnet',cidr_block='10.60.1.0/24',availability_zone='ap-southeast-3a');link('subnet','/vpc_id','vpc')
resources['subnet_b']=json.loads(json.dumps(resources['subnet']));update('subnet_b',cidr_block='10.60.2.0/24',availability_zone='ap-southeast-3b')
for key in ['route_table','internet_gateway','security_group']:link(key,'/vpc_id','vpc')
update('security_group',name='catalog-db-access',description='Example database network access')
update('vpc_security_group_ingress_rule',ip_protocol='tcp',from_port=5432,to_port=5432,cidr_ipv4='10.60.0.0/16');link('vpc_security_group_ingress_rule','/security_group_id','security_group')
update('vpc_security_group_egress_rule',ip_protocol='-1',cidr_ipv4='0.0.0.0/0');link('vpc_security_group_egress_rule','/security_group_id','security_group')
link('nat_gateway','/subnet_id','subnet');link('nat_gateway','/allocation_id','eip')
link('route_table_association','/subnet_id','subnet');link('route_table_association','/route_table_id','route_table')
update('route',destination_cidr_block='0.0.0.0/0');link('route','/route_table_id','route_table');link('route','/gateway_id','internet_gateway')
update('db_subnet_group',name='catalog-db-subnets');link('db_subnet_group','/subnet_ids','subnet');link('db_subnet_group','/subnet_ids','subnet_b')
update('db_instance',identifier='catalog-db',final_snapshot_identifier='catalog-db-final');link('db_instance','/db_subnet_group_name','db_subnet_group','name');link('db_instance','/vpc_security_group_ids','security_group')
update('rds_cluster',cluster_identifier='catalog-aurora',final_snapshot_identifier='catalog-aurora-final');link('rds_cluster','/db_subnet_group_name','db_subnet_group','name');link('rds_cluster','/vpc_security_group_ids','security_group')
update('rds_cluster_instance',identifier='catalog-aurora-1');link('rds_cluster_instance','/cluster_identifier','rds_cluster','cluster_identifier');link('rds_cluster_instance','/engine','rds_cluster','engine')
update('db_parameter_group',name='catalog-pg',family='postgres16');update('rds_cluster_parameter_group',name='catalog-aurora-pg',family='aurora-postgresql16')
update('iam_role',name='catalog-eks-role',assume_role_policy=policy('eks.amazonaws.com'))
update('iam_role_policy_attachment',policy_arn='arn:aws:iam::aws:policy/AmazonEKSClusterPolicy');link('iam_role_policy_attachment','/role','iam_role','name')
update('eks_cluster',name='catalog-eks');link('eks_cluster','/role_arn','iam_role','arn');link('eks_cluster','/vpc_config/0/subnet_ids','subnet');link('eks_cluster','/vpc_config/0/subnet_ids','subnet_b');resources['eks_cluster']['depends_on']=['iam_role_policy_attachment']
resources['worker_role']={'kind':'aws_iam_role','configuration':{'name':'catalog-worker','assume_role_policy':policy('ec2.amazonaws.com')},'links':{},'depends_on':[],'tags':{}}
resources['fargate_role']={'kind':'aws_iam_role','configuration':{'name':'catalog-fargate','assume_role_policy':policy('eks-fargate-pods.amazonaws.com')},'links':{},'depends_on':[],'tags':{}}
for key,role,managed in [('worker_policy','worker_role','AmazonEKSWorkerNodePolicy'),('worker_registry','worker_role','AmazonEC2ContainerRegistryReadOnly'),('fargate_policy','fargate_role','AmazonEKSFargatePodExecutionRolePolicy')]:
 resources[key]={'kind':'aws_iam_role_policy_attachment','configuration':{'policy_arn':'arn:aws:iam::aws:policy/'+managed},'links':{},'depends_on':[],'tags':{}};link(key,'/role',role,'name')
update('eks_node_group',node_group_name='catalog-workers');link('eks_node_group','/cluster_name','eks_cluster','name');link('eks_node_group','/node_role_arn','worker_role','arn');link('eks_node_group','/subnet_ids','subnet');link('eks_node_group','/subnet_ids','subnet_b');resources['eks_node_group']['depends_on']=['worker_policy','worker_registry']
update('eks_fargate_profile',fargate_profile_name='catalog-fargate');link('eks_fargate_profile','/cluster_name','eks_cluster','name');link('eks_fargate_profile','/pod_execution_role_arn','fargate_role','arn');link('eks_fargate_profile','/subnet_ids','subnet');resources['eks_fargate_profile']['depends_on']=['fargate_policy']
update('eks_addon',addon_name='vpc-cni');link('eks_addon','/cluster_name','eks_cluster','name')
update('eks_access_entry',principal_arn='arn:aws:iam::123456789012:role/ExistingClusterOperator',type='STANDARD');link('eks_access_entry','/cluster_name','eks_cluster','name')
update('eks_access_policy_association',principal_arn='arn:aws:iam::123456789012:role/ExistingClusterOperator',policy_arn='arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy',access_scope=[{'type':'cluster'}]);link('eks_access_policy_association','/cluster_name','eks_cluster','name');resources['eks_access_policy_association']['depends_on']=['eks_access_entry']
update('s3_bucket',bucket='replace-with-globally-unique-catalog-bucket')
for key in ['s3_bucket_versioning','s3_bucket_server_side_encryption_configuration','s3_bucket_public_access_block','s3_bucket_policy']:link(key,'/bucket','s3_bucket','id')
update('s3_bucket_policy',policy=json.dumps({'Version':'2012-10-17','Statement':[{'Effect':'Deny','Principal':'*','Action':'s3:*','Resource':['arn:aws:s3:::replace-with-globally-unique-catalog-bucket','arn:aws:s3:::replace-with-globally-unique-catalog-bucket/*'],'Condition':{'Bool':{'aws:SecureTransport':'false'}}}]}))
update('ecr_repository',name='catalog-repository');link('ecr_lifecycle_policy','/repository','ecr_repository','name');update('ecr_lifecycle_policy',policy=json.dumps({'rules':[{'rulePriority':1,'selection':{'tagStatus':'untagged','countType':'sinceImagePushed','countUnit':'days','countNumber':30},'action':{'type':'expire'}}]}))
update('iam_policy',name='catalog-logs',policy=json.dumps({'Version':'2012-10-17','Statement':[{'Effect':'Allow','Action':'logs:DescribeLogGroups','Resource':'*'}]}))
update('iam_role_policy',name='catalog-inline',policy=json.dumps({'Version':'2012-10-17','Statement':[{'Effect':'Allow','Action':'logs:DescribeLogGroups','Resource':'*'}]}));link('iam_role_policy','/role','iam_role','name')
update('iam_instance_profile',name='catalog-instance-profile');link('iam_instance_profile','/role','worker_role','name')
update('cloudwatch_log_group',name='/catalog/application')
update('cloudwatch_metric_alarm',alarm_name='catalog-cpu',comparison_operator='GreaterThanThreshold',evaluation_periods=2,metric_name='CPUUtilization',namespace='AWS/EC2',period=300,statistic='Average',threshold=80)
update('route53_zone',name='catalog.example.invalid')
update('route53_record',name='catalog.example.invalid',type='A',ttl=300,records=['192.0.2.1']);link('route53_record','/zone_id','route53_zone','zone_id')
update('acm_certificate',domain_name='catalog.example.invalid')
link('acm_certificate_validation','/certificate_arn','acm_certificate','arn');update('acm_certificate_validation',validation_record_fqdns=['_replace-validation.catalog.example.invalid'])
update('cloudfront_origin_access_control',name='catalog-oac')
update('cloudfront_distribution',enabled=True,origin=[{'domain_name':'placeholder.invalid','origin_id':'s3','s3_origin_config':[{'origin_access_identity':''}]}],default_cache_behavior=[{'allowed_methods':['GET','HEAD'],'cached_methods':['GET','HEAD'],'target_origin_id':'s3','viewer_protocol_policy':'redirect-to-https','forwarded_values':[{'query_string':False,'cookies':[{'forward':'none'}]}]}],restrictions=[{'geo_restriction':[{'restriction_type':'none'}]}],viewer_certificate=[{'cloudfront_default_certificate':True}])
link('cloudfront_distribution','/origin/0/domain_name','s3_bucket','bucket_regional_domain_name');link('cloudfront_distribution','/origin/0/origin_access_control_id','cloudfront_origin_access_control','id')
example={'name':'catalog-example','environments':{'dev':{'backend':{'type':'local'},'values':{'aws_region':'ap-southeast-3','aws_profile':None,'tags':{'env':'dev','project':'catalog-example'},'instances':{},'security_groups':{},'load_balancers':{},'managed_resources':resources}}}}
Path('examples/catalog-complete.json').write_text(json.dumps(example,indent=2)+'\n')
print('Generated placeholder fixture:',len(resources),'managed resources')
