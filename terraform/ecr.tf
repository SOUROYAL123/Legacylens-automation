resource "aws_ecr_repository" "legacylens_repo" {
  name                 = "legacylens-repo"
  image_tag_mutability = "MUTABLE"

  # Automatically scan your Docker images for vulnerabilities on push
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = "legacylens-production-repository" }
}

# Optional: Add a lifecycle policy so you don't pay to store 100 old images
resource "aws_ecr_lifecycle_policy" "repo_policy" {
  repository = aws_ecr_repository.legacylens_repo.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = {
        type = "expire"
      }
    }]
  })
}

# Output the repository URL so you can easily copy it for your Docker push commands
output "ecr_repository_url" {
  value = aws_ecr_repository.legacylens_repo.repository_url
}