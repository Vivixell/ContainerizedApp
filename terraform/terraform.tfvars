vpc_cidr_blocks    = "10.0.0.0/16"
subnet_cidr_blocks = "10.0.1.0/24"
avail_zone         = "us-west-1a"
instance_type      = "t3.medium" 

# public_key isn't passed here to GitHub Actions; I used this in local
