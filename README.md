# letsencrypt-kubernetes
Kubernetes Automation for Let's Encrypt

The process below caters to GKE, but originally ran in a kubespray cluster on OpenStack. It should be easy to adapt to another kubernetes provider. I also use NS1 for DNS, but the excellent acme.sh client supports many others.

 1. Create a namespace where Let's Encrypt automation will be deployed
 1. Create the ClusterRole, ClusterRoleBinding and ServiceAccount that will be used to monitor namespaces
 1. Create a PersistentVolume (PV) amd PersistentVolumeClaim (PVC) where the certificates will be stored
 1. Update the configuration file from the template
 1. Create a ConfigMap from the configuration file
 1. Create the deployment
 1. Update any namespace that should have a certificate generated