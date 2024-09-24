# Use s3 bucket to store terraform state files
terraform {
  backend "s3" {
    bucket = "demo1-backend-bucket"  
    key    = "terraform/state"
    region = "ap-south-1"
  }
}