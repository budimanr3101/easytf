#!/usr/bin/env python3
"""Build the curated resource catalog from the locally pinned AWS provider schema."""
import json,sys
from pathlib import Path
schema_path=Path(sys.argv[1] if len(sys.argv)>1 else 'test-output/aws-schema.json')
resources=json.loads(schema_path.read_text())['provider_schemas']['registry.terraform.io/hashicorp/aws']['resource_schemas']
groups={
 'Databases': {'aws_db_instance':'RDS instance','aws_db_subnet_group':'DB subnet group','aws_db_parameter_group':'DB parameter group','aws_rds_cluster':'Aurora cluster','aws_rds_cluster_instance':'Aurora instance','aws_rds_cluster_parameter_group':'Aurora parameter group'},
 'Kubernetes': {'aws_eks_cluster':'EKS cluster','aws_eks_node_group':'EKS managed node group','aws_eks_fargate_profile':'EKS Fargate profile','aws_eks_addon':'EKS add-on','aws_eks_access_entry':'EKS access entry','aws_eks_access_policy_association':'EKS access policy association'},
 'Storage & images': {'aws_s3_bucket':'S3 bucket','aws_s3_bucket_versioning':'S3 versioning','aws_s3_bucket_server_side_encryption_configuration':'S3 encryption','aws_s3_bucket_public_access_block':'S3 public access block','aws_s3_bucket_policy':'S3 bucket policy','aws_ecr_repository':'ECR repository','aws_ecr_lifecycle_policy':'ECR lifecycle policy'},
 'IAM & observability': {'aws_iam_role':'IAM role','aws_iam_policy':'IAM policy','aws_iam_role_policy_attachment':'IAM role policy attachment','aws_iam_role_policy':'IAM inline policy','aws_iam_instance_profile':'IAM instance profile','aws_cloudwatch_log_group':'CloudWatch log group','aws_cloudwatch_metric_alarm':'CloudWatch metric alarm'},
 'Networking': {'aws_vpc':'VPC','aws_subnet':'Subnet','aws_route_table':'Route table','aws_route':'Route','aws_route_table_association':'Route table association','aws_internet_gateway':'Internet gateway','aws_eip':'Elastic IP','aws_nat_gateway':'NAT gateway','aws_security_group':'Security group (VPC links)','aws_vpc_security_group_ingress_rule':'Security group ingress rule','aws_vpc_security_group_egress_rule':'Security group egress rule'},
 'DNS & edge': {'aws_route53_zone':'Route53 hosted zone','aws_route53_record':'Route53 record','aws_acm_certificate':'ACM certificate','aws_acm_certificate_validation':'ACM certificate validation','aws_cloudfront_distribution':'CloudFront distribution','aws_cloudfront_origin_access_control':'CloudFront origin access control'}
}
presets={
 'aws_db_instance': {'engine':'postgres','instance_class':'db.t3.micro','allocated_storage':20,'storage_type':'gp3','storage_encrypted':True,'manage_master_user_password':True,'username':'dbadmin','backup_retention_period':7,'publicly_accessible':False,'deletion_protection':True,'skip_final_snapshot':False},
 'aws_rds_cluster': {'engine':'aurora-postgresql','manage_master_user_password':True,'master_username':'dbadmin','storage_encrypted':True,'backup_retention_period':7,'deletion_protection':True,'skip_final_snapshot':False},
 'aws_rds_cluster_instance':{'engine':'aurora-postgresql','instance_class':'db.r6g.large','publicly_accessible':False},
 'aws_eks_cluster':{'vpc_config':[{'endpoint_private_access':True,'endpoint_public_access':False,'subnet_ids':[]}], 'access_config':[{'authentication_mode':'API','bootstrap_cluster_creator_admin_permissions':False}]},
 'aws_eks_node_group':{'capacity_type':'ON_DEMAND','instance_types':['t3.medium'],'scaling_config':[{'min_size':1,'desired_size':2,'max_size':3}]},
 'aws_eks_fargate_profile':{'selector':[{'namespace':'default'}]},
 'aws_s3_bucket':{'force_destroy':False},
 'aws_s3_bucket_versioning':{'versioning_configuration':[{'status':'Enabled'}]},
 'aws_s3_bucket_public_access_block':{'block_public_acls':True,'block_public_policy':True,'ignore_public_acls':True,'restrict_public_buckets':True},
 'aws_s3_bucket_server_side_encryption_configuration':{'rule':[{'apply_server_side_encryption_by_default':[{'sse_algorithm':'AES256'}]}]},
 'aws_ecr_repository':{'image_tag_mutability':'IMMUTABLE','image_scanning_configuration':[{'scan_on_push':True}],'force_delete':False},
 'aws_cloudwatch_log_group':{'retention_in_days':30}, 'aws_vpc':{'enable_dns_support':True,'enable_dns_hostnames':True},
 'aws_subnet':{'map_public_ip_on_launch':False}, 'aws_eip':{'domain':'vpc'},
 'aws_acm_certificate':{'validation_method':'DNS'}, 'aws_cloudfront_origin_access_control':{'origin_access_control_origin_type':'s3','signing_behavior':'always','signing_protocol':'sigv4'}
}
def type_node(t,required=False,help=''):
 n={'kind':'string' if t=='string' else 'bool' if t=='bool' else 'number' if t=='number' else 'any','required':required,'help':help}
 if isinstance(t,list):
  kind,el=t
  if kind in ('list','set'): n.update(kind='list',element=type_node(el))
  elif kind=='map': n.update(kind='map',element=type_node(el))
  elif kind=='object': n.update(kind='object',properties={k:type_node(v) for k,v in el.items()})
  else: n['kind']='any'
 return n

def node(block,depth=0):
 props={}
 for k,a in block.get('attributes',{}).items():
  if k=='timeouts' or (k=='id' and depth==0) or k.endswith('_wo_version') or a.get('sensitive') or a.get('write_only') or k.endswith('_wo') or a.get('deprecated') or not (a.get('required') or a.get('optional')):continue
  props[k]=type_node(a.get('type','dynamic'),a.get('required',False),a.get('description',''))
 for k,b in block.get('block_types',{}).items():
  if k=='timeouts':continue
  child=node(b['block'],depth+1); n={'kind':'list','required':b.get('min_items',0)>0,'element':child,'help':b['block'].get('description','')}
  if 'max_items' in b:n['max_items']=b['max_items']
  props[k]=n
 return {'kind':'object','properties':props,'required':True}

def blocks(block,base='var.settings',depth=0):
 lines=[]
 for k,a in block.get('attributes',{}).items():
  if k=='timeouts' or (k=='id' and depth==0) or k.endswith('_wo_version') or a.get('sensitive') or a.get('write_only') or k.endswith('_wo') or a.get('deprecated') or not(a.get('required') or a.get('optional')):continue
  expr=f'try({base}.{k}, null)'
  if depth==0 and k=='tags':expr=f'merge(var.environment_tags, coalesce(try({base}.tags, null), {{}}), var.resource_tags)'
  lines.append(f'{k} = {expr}')
 for k,b in block.get('block_types',{}).items():
  if k=='timeouts':continue
  iterator=f'b{depth}'
  expr=f'coalesce(try({base}.{k}, null), [])'
  lines+= [f'dynamic "{k}" {{',f'  for_each = {expr}',f'  iterator = {iterator}','  content {']
  lines+=['    '+x for x in blocks(b['block'],f'{iterator}.value',depth+1)]
  lines+=['  }','}']
 return lines
catalog={}
output_root=Path('templates/catalog');output_root.mkdir(exist_ok=True)
for category,entries in groups.items():
 for kind,title in entries.items():
  block=resources[kind]['block']; definition=node(block)
  outputs={k:type_node(a['type'])['kind'] for k,a in block.get('attributes',{}).items() if not a.get('sensitive') and not a.get('deprecated') and a.get('type') in ('string','number','bool') and (a.get('computed') or k in ('name','bucket','identifier','cluster_identifier','cluster_name','engine','engine_version'))}
  defaults=presets.get(kind,{})
  catalog[kind]={'title':title,'category':category,'schema':definition,'outputs':outputs,'defaults':defaults}
  folder=output_root/kind;folder.mkdir(exist_ok=True)
  text='variable "settings" { type = any }\nvariable "environment_tags" { type = map(string) }\nvariable "resource_tags" { type = map(string) }\n'
  text+=f'resource "{kind}" "this" {{\n'+'\n'.join('  '+x for x in blocks(block))+'\n}\n'
  text+='output "fields" {\n  value = {\n'+'\n'.join(f'    {k} = {kind}.this.{k}' for k in outputs)+'\n  }\n}\n'
  (folder/'main.tf').write_text(text)
Path('schemas/resource-catalog.json').write_text(json.dumps({'provider_version':'6.68.0','resources':catalog},indent=2)+'\n')
print(f'Generated {len(catalog)} curated AWS resources')

lines = ["// Generated catalog template inventory.", "pub fn template(kind: &str) -> Option<&'static str> {", "    match kind {"]
for kind in sorted(catalog):
 lines.append(f'        "{kind}" => Some(include_str!("../templates/catalog/{kind}/main.tf")),')
lines += ["        _ => None,", "    }", "}"]
Path("src/catalog_templates.rs").write_text("\n".join(lines) + "\n")
