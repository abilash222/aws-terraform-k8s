# Terraform Google GKE Cluster And Application Deployment

A Terraform module to crete a Google Kubernetes Engine (GKE) cluster and install sample kubernetes application

# Installation Prerequisites
Terraform
gcloud
kubectl


Extract the package:

Change necessary variables in file vars.tfvars file.

```
cd gke-cluster 
terraform init
terrafrom apply -var-file=vars.tfvars
```

check for the output and try to access the application

*kubectl command is necessary since terraform doesn't support custom resource definition
