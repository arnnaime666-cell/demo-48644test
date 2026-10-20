resource "vercel_project" "educateed" {
  name      = "educateed"
  framework = "nextjs"
  team_id   = var.vercel_team_id

  node_version      = "24.x"
  directory_listing = false

  lifecycle {
    # Environment variables stay managed in Vercel until a secure remote state
    # and secret injection workflow are in place.
    ignore_changes = [environment]
  }
}

