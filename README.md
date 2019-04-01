# letsencrypt-kubernetes
Kubernetes Automation for Let's Encrypt

The process below caters to GKE, but originally ran in a kubespray cluster on OpenStack. It should be easy to adapt to another kubernetes provider. I also use NS1 for DNS, but the excellent acme.sh client supports many others.

 1. Create the ClusterRole, ClusterRoleBinding and ServiceAccount that will be used to monitor namespaces
 1. Create a namespace where Let's Encrypt automation will be deployed: 
 1. Create a PersistentVolume (PV) amd PersistentVolumeClaim (PVC) where the certificates will be stored
 1. Generate an NS1 API Key for DNS domain validation
 1. Update the configuration file from the template
 1. Create a ConfigMap from the configuration file
 1. Create the deployment
 1. Update any namespace that should have a certificate generated

## Establish cluster access
`kubectl create serviceaccount letsencrypt -n kube-system`
`kubectl apply -f le-clusterrole.yaml`

The following commands will reveal the token you need to add to the configuration file below

```
$ kubectl get sa letsencrypt -o yaml -n kube-system
apiVersion: v1
kind: ServiceAccount
metadata:
  creationTimestamp: "2019-04-01T13:56:34Z"
  name: letsencrypt
  namespace: kube-system
  resourceVersion: "5428395"
  selfLink: /api/v1/namespaces/kube-system/serviceaccounts/letsencrypt
  uid: f62ae170-5485-11e9-a73b-42010a80004d
secrets:
- name: letsencrypt-token-v5khc
$ kubectl describe secret letsencrypt-token-v5khc -n kube-system
Name:         letsencrypt-token-v5khc
Namespace:    kube-system
Labels:       <none>
Annotations:  kubernetes.io/service-account.name: letsencrypt
              kubernetes.io/service-account.uid: f62ae170-5485-11e9-a73b-42010a80004d

Type:  kubernetes.io/service-account-token

Data
====
ca.crt:     1115 bytes
namespace:  11 bytes
token:      eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c
```

The above commands create a ServiceAccount with permissions to *ALL* Secrets in the cluster.

## Create namespace
`kubectl create ns letsencrypt`

## Create PersistentVolume
TLS certificates don't take up a lot of space, so the PersistentVolume only needs a few GB. In GKE, the PersistentVolume will be automatically created when you create the PersistentVolumeClaim below (https://cloud.google.com/kubernetes-engine/docs/concepts/persistent-volumes).
`kubectl apply -f le-pvc.yaml`

## Generate NS1 Key
Login to https://my.nsone.net/ and click on your username (top left) and the click on "Account Settings". There are four tabs, the one on the far right is API KEYS. From there, choose "Add Key" and uncheck everything except the DNS checkboxes. Capture the key to be used later when updating the configuration file.

## Update the configuration file
Perform the following steps using `letsencrypt-automation.conf.json.template`

 * Copy the `token` above into the configuration template, e.g. `"onboarding_serviceaccount_token": "TOKEN"`
 * ~~In the GKE console, find the Endpoint IP and copy it into the configuration file, e.g. `"api_host": "35.194.40.218"`~~ On GKE, it's best to use `kubernetes.default`
 * Decide what to do with `ssl_verify`
   * It's possible to skip the SSL verification: `"ssl_verify": false`. If you choose this, you will need to remove the ConfigMap and VolumeMount references in the deployment YAML.
   * You can also verify by going to the GKE console, find the CA certificate for the above endpoint, and copy it into a file, such as `gke-ca`. Now create ConfigMap `kubectl create cm letsencrypt-gke-ca --dry-run -o yaml --from-file=gke-ca=/kubeyaml/letsencrypt-kubernetes/gke-ca -n letsencrypt | kubectl apply -f - -n letsencrypt`.
 * Copy in the NS1 API Key generated above.
 * If you set `acme_sh_test: true`, it will operate against Let's Encrypt staging environment, which won't count against your quotas, but it also won't produce valid signed certificates.

## Create a ConfigMap for the configuration file
Using the above template file, create a ConfigMap for the configuration file:

`kubectl create cm letsencrypt-config --dry-run -o yaml --from-file=letsencrypt-automation.conf.json=/kubeyaml/letsencrypt-kubernetes/conf/letsencrypt-automation.conf.json.template -n letsencrypt | kubectl apply -f - -n letsencrypt`

## Deploy Let's Encrypt
At this point create the Deployment.
`kubectl apply -f /kubeyaml/Documents/work/letsencrypt-kubernetes/le-deployment.yaml`

The Deployment can be validated by examining the Pod
```
$ kubectl get pod -n letsencrypt --watch
NAME                           READY   STATUS              RESTARTS   AGE
letsencrypt-865bf5547c-zlbmh   1/1     Running             0          11s
$ kubectl exec -it letsencrypt-865bf5547c-zlbmh -n letsencrypt -- /bin/sh
/ # ls
acme.sh  automation  bin  dev  entry.sh  etc  home  lib  media  mnt  opt  proc  requirements  root  run  sbin  srv  sys  tmp  usr  var
/ # df -h
Filesystem      Size  Used Avail Use% Mounted on
/dev/sdb        2.0G  6.0M  1.9G   1% /acme.sh
/ # ls -la /acme.sh/
total 24
drwxr-xr-x 3 root root  4096 Apr  1 15:02 .
drwxr-xr-x 1 root root  4096 Apr  1 15:12 ..
drwx------ 2 root root 16384 Apr  1 15:02 lost+found
/ # ls /automation/
ca  conf  letsencrypt-automation.py
/ # ls /automation/conf/
letsencrypt-automation.conf.json
/ # ls /automation/ca
gke-ca
/ # crontab -l
43 0 * * * "/root/.acme.sh"/acme.sh --cron --home "/root/.acme.sh" --config-home "/acme.sh"
*/5 * * * * /usr/bin/python /automation/letsencrypt-automation.py
```


