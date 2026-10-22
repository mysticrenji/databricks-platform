output "roles" {
  description = "Dedicated storage-role ARNs and trust configuration status."
  value = { for key, role in aws_iam_role.this : key => {
    arn              = role.arn
    trust_configured = contains(keys(var.trust), key)
  } }
  depends_on = [aws_iam_role_policy.this]
}
