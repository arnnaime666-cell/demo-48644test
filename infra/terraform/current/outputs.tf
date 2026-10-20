output "vercel_project_id" {
  value = vercel_project.educateed.id
}

output "supabase_project_ref" {
  value = supabase_project.educateed.id
}

output "managed_app_domain" {
  value = local.app_domain
}

