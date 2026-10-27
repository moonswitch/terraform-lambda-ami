locals {
  merge_tags     = merge(var.default_tags, var.tags)
  function_name  = "update_node_group_function_${var.cluster}"
  eks_arn_prefix = "arn:${data.aws_partition.current.partition}:eks:${var.region}:${data.aws_caller_identity.current.account_id}"
}
