variable "owners" {
  description = "Additional owners (object IDs) of the gateway app registration; the identity running the stack is always an owner."
  type        = set(string)
  default     = []
  nullable    = false
}
