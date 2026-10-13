output "load_balancers" {
  value = { for key, lb in module.load_balancers : key => {
    arn           = lb.arn
    dns_name      = lb.dns_name
    zone_id       = lb.zone_id
    target_groups = lb.target_groups
    listeners     = lb.listeners
    attachments   = lb.attachments
    tags          = lb.tags
  } }
}
