# resource "aws_iam_role" "ec2_ecr_access_role" {
#   name = "${var.proj_name}-ec2-ecr-access-role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = "sts:AssumeRole"
#         Effect = "Allow"
#         Principal = {
#           Service = "ec2.amazonaws.com"
#         }
#       }
#     ]
#   })

#   tags = {
#     Name = "${var.proj_name}-ec2-ecr-access-role"
#   }
# }

# resource "aws_iam_role_policy_attachment" "ecr_read_only" {
#   role       = aws_iam_role.ec2_ecr_access_role.name
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
# }

# resource "aws_iam_instance_profile" "ec2_profile" {
#   name = "${var.proj_name}-ec2-profile"
#   role = aws_iam_role.ec2_ecr_access_role.name
# }
