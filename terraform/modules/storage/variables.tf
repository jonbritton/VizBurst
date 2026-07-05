variable "name_prefix" {
  description = "Prefix for all resource names."
  type        = string
}

variable "assets_expire_days" {
  description = "Days before asset-library objects expire. The delta-sync re-uploads anything a new job still needs, so this just prunes cold shows."
  type        = number
  default     = 90
}

variable "frames_expire_days" {
  description = "Days before rendered frames expire from the output bucket. Frames are pulled on-prem within hours; this is the safety margin."
  type        = number
  default     = 14
}

variable "tags" {
  description = "Map of tags to apply to all resources."
  type        = map(string)
  default     = {}
}
