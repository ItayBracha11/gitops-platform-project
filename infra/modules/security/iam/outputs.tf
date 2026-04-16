output "alb_controller_role_arn" {
  description = "IAM Role ARN for the ALB Controller Service Account"
  value       = aws_iam_role.alb_controller.arn
}