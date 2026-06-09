variable "resource_group_name"   { type = string }
variable "location"               { type = string }
variable "tags"                   { type = map(string) }
variable "account_name"           { type = string }
variable "throughput_rus"         { type = number }
variable "public_network_access"  { type = string }
variable "subnet_id"              { type = string }
variable "vnet_id"                { type = string }
variable "dns_zone_id"            { type = string }
variable "managed_identity_principal_id" { type = string }
variable "log_analytics_id"       { 
    type = string
    default = "" 
}
