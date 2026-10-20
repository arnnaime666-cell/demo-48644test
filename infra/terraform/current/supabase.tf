resource "supabase_project" "educateed" {
  organization_id   = var.supabase_organization_id
  name              = "EducateEd"
  region            = "us-east-2"
  database_password = var.supabase_database_password

  lifecycle {
    ignore_changes = [database_password]
  }
}

resource "supabase_settings" "educateed" {
  project_ref = var.supabase_project_ref

  api = jsonencode({
    db_schema            = "public,storage,graphql_public"
    db_extra_search_path = "public,extensions"
    max_rows             = 1000
  })

  storage = jsonencode({
    fileSizeLimit = 52428800
    features = {
      imageTransformation = {
        enabled = true
      }
      s3Protocol = {
        enabled = false
      }
    }
  })
}

