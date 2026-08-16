# One repository, both images distinguished by tag (orchestrator:<tag>,
# executor:<tag>), per the spec.

resource "aws_ecr_repository" "this" {
  name                 = var.ecr_repository_name
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  # Demo repo: let `terraform destroy` remove it even if it still has images, instead
  # of requiring a manual `aws ecr batch-delete-image` first. Not a pattern to carry
  # into a repo holding anything you'd actually miss.
  force_delete = true
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the 10 most recent images per tag prefix"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
