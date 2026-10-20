variable "vercel_team_id" {
  description = "Vercel team ID that owns the EducateED project."
  type        = string
}

variable "vercel_project_id" {
  description = "Existing Vercel project ID for EducateED."
  type        = string
}

variable "supabase_project_ref" {
  description = "Existing Supabase project reference."
  type        = string
}

variable "supabase_organization_id" {
  description = "Supabase organization slug/ID."
  type        = string
}

variable "supabase_database_password" {
  description = "Existing Supabase database password. Required by the provider for imported project resources; ignored after import."
  type        = string
  sensitive   = true
}
