"""Build checked-in EC2 templates/catalog from the pinned provider schema, offline."""
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
raw = json.loads((ROOT / 'schemas/aws-instance-6.68.0.json').read_text())
owned = {'ami','instance_type','subnet_id','vpc_security_group_ids','associate_public_ip_address','tags','id','tags_all','region','security_groups'}
hints = {
'iam_instance_profile':'Optional existing IAM instance profile name, not a role ARN. The profile contains the EC2 role.',
'key_name':'Optional existing EC2 key pair name in this region. Leave unset for SSM-only access.',
'user_data':'Optional boot script. Paste multiline text; Ctrl+S saves the text editor. Do not include secrets.',
'user_data_base64':'Optional base64 boot data; conflicts with user_data.',
'root_block_device':'Optional root disk overrides. Unset keeps the legacy root size with encrypted gp3.',
'ebs_block_device':'Optional additional EBS disks. Add one entry per device. Terraform manages all non-root EBS mappings; do not mix with external attachments.',
'primary_network_interface':'Optional existing primary ENI. It owns subnet/SG/IP settings; clear instance SG and public IP settings.',
'network_interface':'Optional legacy ENI attachments (deprecated by provider). Prefer primary_network_interface and separate attachment resources.',
'launch_template':'Optional existing launch template. Explicit basic settings override template values. Root disk defaults are omitted when using a template.',
'source_dest_check':'Optional source/destination checking. Disable only when this instance routes traffic.',
'force_destroy':'Optional force destruction when stop/termination protection blocks deletion. Review before enabling.',
'private_ip':'Optional private IPv4 address; it must belong to the subnet.',
}
hints.update({
'availability_zone':'Optional availability zone. Must match the selected subnet.',
'disable_api_stop':'Optional protection against stopping the instance through the EC2 API.',
'disable_api_termination':'Optional protection against terminating the instance through the EC2 API.',
'ebs_optimized':'Optional EBS optimized IO; availability depends on instance type.',
'enable_primary_ipv6':'Optional primary IPv6 address behavior; requires IPv6 networking support.',
'get_password_data':'Optional retrieval of encrypted Windows administrator password data.',
'hibernation':'Optional EC2 hibernation support; AMI, instance type and root disk must support it.',
'host_id':'Optional dedicated host ID; conflicts with host_resource_group_arn.',
'host_resource_group_arn':'Optional dedicated host resource group ARN; conflicts with host_id.',
'instance_initiated_shutdown_behavior':'Optional stop or terminate behavior when the OS shuts down.',
'ipv6_address_count':'Optional number of IPv6 addresses. Do not also set ipv6_addresses.',
'ipv6_addresses':'Optional explicit IPv6 addresses; subnet must support IPv6.',
'monitoring':'Optional detailed CloudWatch monitoring; AWS charges may apply.',
'placement_group':'Optional placement group name; do not also set placement_group_id.',
'placement_group_id':'Optional placement group ID; do not also set placement_group.',
'placement_partition_number':'Optional partition within a partition placement group.',
'secondary_private_ips':'Optional secondary private IPv4 addresses in the selected subnet.',
'tenancy':'Optional default, dedicated, or host tenancy; instance type and placement must support it.',
'user_data_replace_on_change':'Optional replacement when boot user data changes; review the Terraform plan.',
'volume_tags':'Optional tags for volumes; do not combine with tags on individual block devices.',
'capacity_reservation_specification':'Optional capacity reservation preference and target.',
'capacity_reservation_target':'Optional capacity reservation ID or resource group ARN.',
'cpu_options':'Optional CPU core/thread, AMD SEV-SNP and nested virtualization settings.',
'credit_specification':'Optional CPU credit behavior for burstable instances.',
'enclave_options':'Optional Nitro Enclaves configuration; requires a compatible instance.',
'ephemeral_block_device':'Optional instance-store mappings; device and instance type must support them.',
'instance_market_options':'Optional market type and Spot request settings.',
'maintenance_options':'Optional automatic recovery behavior.',
'metadata_options':'Optional EC2 instance metadata settings. http_tokens=required enables IMDSv2 enforcement.',
'private_dns_name_options':'Optional private DNS hostname type and IPv4/IPv6 DNS records.',
'secondary_network_interface':'Optional secondary-network ENI configuration; requires supported EC2/network features.',
'timeouts':'Optional Terraform operation timeouts, for example create=30m.',
'device_name':'Required EBS device mapping name, for example /dev/sdf. Guest NVMe names may differ.',
'volume_size':'Optional disk size in GiB. For additional EBS, provide this or a snapshot_id.',
'volume_type':'Optional standard, gp2, gp3, io1, io2, st1, or sc1 volume type.',
'encrypted':'Optional disk encryption; a KMS key requires encryption.',
'kms_key_id':'Optional KMS key ARN/ID for disk encryption.',
'iops':'Optional provisioned IOPS; compatible volume type and size are required.',
' throughput':'Optional provisioned throughput for gp3 volumes.',
'delete_on_termination':'Optional deletion of this disk/interface when the instance terminates.',
'snapshot_id':'Optional EBS snapshot to initialize an additional volume.',
'network_interface_id':'Required existing network interface ID, for example eni-0123456789abcdef0.',
'http_tokens':'Optional optional or required; required enforces IMDSv2 tokens.',
'http_endpoint':'Optional enabled or disabled metadata endpoint.',
'http_put_response_hop_limit':'Optional metadata response hop limit, 1–64.',
'http_protocol_ipv6':'Optional enabled or disabled IPv6 metadata endpoint.',
'instance_metadata_tags':'Optional enabled or disabled access to instance tags through metadata.',
})
hints['throughput'] = hints.pop(' throughput')

def scalar(t,required=False,name=''):
 if isinstance(t,str): return {'kind':t,'required':required,'help':hints.get(name,'Optional; unset uses the AWS provider default.' if not required else 'Required when this section or entry is enabled.')}
 k,el=t
 return {'kind':'map' if k=='map' else 'list','required':required,'help':hints.get(name,'Optional collection; Enter opens the entry editor.'),'element':scalar(el,True)}
def node(block):
 props={}
 for k,a in block.get('attributes',{}).items():
  if (a.get('optional') or a.get('required')) and k not in ('id','tags_all','volume_id'):
   props[k]=scalar(a['type'],a.get('required',False),k)
 for k,b in block.get('block_types',{}).items():
  child=node(b['block'])
  props[k]=dict(child,help=hints.get(k,'Optional section; unset leaves the provider default.')) if b['nesting_mode']=='single' else {'kind':'list','element':child,'max_items':b.get('max_items'),'help':hints.get(k,'Optional section; add an entry to enable it.')}
 return {'kind':'object','properties':props,'help':'Optional configuration. Select a setting to edit; unset values use provider defaults.'}
catalog=node(raw)
catalog['properties']['instance_role'] = scalar('string', False, 'instance_role')
catalog['properties']['instance_role']['help'] = 'Optional existing IAM role NAME. EasyTF creates an instance profile for it; do not also set iam_instance_profile.'
for k in owned:catalog['properties'].pop(k,None)
(ROOT/'schemas/ec2-options.json').write_text(json.dumps(catalog,indent=2)+'\n')
def hcltype(n):
 if n['kind'] in ('string','number','bool'):return n['kind']
 if n['kind'] in ('list','map'):return n['kind']+'('+hcltype(n['element'])+')'
 return 'object({\n'+''.join('    '+k+' = '+(hcltype(v) if v.get('required') else 'optional('+hcltype(v)+')')+'\n' for k,v in n['properties'].items())+'  })'
def lines(block,expr,indent,skip=()):
 out=''
 for k,a in block.get('attributes',{}).items():
  if k in skip or k in ('id','tags_all','volume_id') or not(a.get('optional') or a.get('required')):continue
  out+=indent+k+' = '+expr+'.'+k+'\n'
 for k,b in block.get('block_types',{}).items():
  if k in skip:continue
  source=expr+'.'+k
  each=k+'_item'
  collection=source+' == null ? [] : ['+source+']' if b['nesting_mode']=='single' else source+' == null ? [] : '+source
  if k=='root_block_device' and expr=='var.configuration':
   collection='local.root_devices'
  out+=indent+'dynamic "'+k+'" {\n'+indent+'  for_each = '+collection+'\n'+indent+'  iterator = '+each+'\n'+indent+'  content {\n'+lines(b['block'],each+'.value',indent+'    ')+indent+'  }\n'+indent+'}\n'
 return out
base=(ROOT/'schemas/ec2-base.tf').read_text()
header='''data "aws_network_interface" "existing" {
  for_each = toset(concat(
    [for eni in coalesce(var.configuration.primary_network_interface, []) : eni.network_interface_id],
    [for eni in coalesce(var.configuration.network_interface, []) : eni.network_interface_id]
  ))
  id = each.key
}
data "aws_iam_role" "existing" {
  count = var.configuration.instance_role == null ? 0 : 1
  name = var.configuration.instance_role
}
resource "aws_iam_instance_profile" "role" {
  count = var.configuration.instance_role == null ? 0 : 1
  name_prefix = "${var.resource_key}-"
  role = data.aws_iam_role.existing[0].name
  tags = var.tags
}

locals {
  eni_mode = length(coalesce(var.configuration.primary_network_interface, [])) > 0 || length(coalesce(var.configuration.network_interface, [])) > 0
  root_devices = length(coalesce(var.configuration.root_block_device, [])) > 0 ? var.configuration.root_block_device : length(coalesce(var.configuration.launch_template, [])) > 0 ? [] : [ {
    delete_on_termination = true
    encrypted = true
    iops = null
    kms_key_id = null
    tags = null
    throughput = null
    volume_size = var.root_volume_gib
    volume_type = "gp3"
  } ]
}
'''
base=base.replace('  tags = merge',lines(raw,'var.configuration','  ',owned)+'\n  tags = merge')
base = base.replace('iam_instance_profile = var.configuration.iam_instance_profile', 'iam_instance_profile = var.configuration.instance_role == null ? var.configuration.iam_instance_profile : aws_iam_instance_profile.role[0].name')
(ROOT/'templates/ec2_main.tf').write_text(header+'\n'+base)
vfile=ROOT/'templates/ec2_variables.tf'
v=(ROOT/'schemas/ec2-variables-base.tf').read_text()
v+='\nvariable "resource_key" {\n  type = string\n  default = "instance"\n}\n'
v+='\nvariable "configuration" {\n  description = "Optional EC2 settings from AWS provider 6.68.0; null leaves provider defaults."\n  type = '+hcltype(catalog)+'\n  default = {}\n}\n'
vfile.write_text(v)
rfile=ROOT/'templates/root_variables.tf'
r=(ROOT/'schemas/root-variables-base.tf').read_text()
r=r.replace('    tags                        = optional(map(string), {})', '    configuration = optional('+hcltype(catalog)+', {})\n    tags                        = optional(map(string), {})',1)
rfile.write_text(r)
