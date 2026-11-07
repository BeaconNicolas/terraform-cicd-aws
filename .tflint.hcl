# TFLint configuration shared by all stacks.
# Only the bundled Terraform ruleset is used, so no plugins are downloaded at run time.
config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "all"
}
