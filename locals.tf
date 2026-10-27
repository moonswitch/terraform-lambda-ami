locals {
  merge_tags = merge(var.default_tags, var.tags)
}
