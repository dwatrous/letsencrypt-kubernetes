#!/bin/bash

# Here is a script to deploy cert to a kubernetes cluster.

#returns 0 means success, otherwise error.

########  Public functions #####################

#domain keyfile certfile cafile fullchain
kubernetes_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  DEFAULT_K8S_PORT="6443"
  if [ -z "${DEPLOY_K8S_PORT}" ]; then
    _k8sport="${DEFAULT_K8S_PORT}"
    _cleardomainconf DEPLOY_K8S_PORT
  else
    _k8sport="${DEPLOY_K8S_PORT}"
    _savedomainconf DEPLOY_K8S_PORT "$DEPLOY_K8S_PORT"
  fi
  DEFAULT_K8S_SCHEME="https"
  if [ -z "${DEPLOY_K8S_SCHEME}" ]; then
    _k8sscheme="${DEFAULT_K8S_SCHEME}"
    _cleardomainconf DEPLOY_K8S_SCHEME
  else
    _k8sscheme="${DEPLOY_K8S_SCHEME}"
    _savedomainconf DEPLOY_K8S_SCHEME "$DEPLOY_K8S_SCHEME"
  fi
  _k8surl="${DEPLOY_K8S_URL}"
  if [ -z "$_k8surl" ]; then
    _err "Kubernetes cluster URL not found. Please define DEPLOY_K8S_URL."
    return 1
  fi
  _savedomainconf DEPLOY_K8S_URL "$DEPLOY_K8S_URL"
  # build the full URL to the kubernetes cluster
  _k8sfullurl="$_k8sscheme://$_k8surl:$_k8sport"
  _info "Full URL to kubernetes cluster $_k8sfullurl"

  _k8snamespace="${DEPLOY_K8S_NAMESPACE}"
  if [ -z "$_k8snamespace" ]; then
    _err "Kubernetes namespace not found. Please define DEPLOY_K8S_NAMESPACE."
    return 1
  fi
  _savedomainconf DEPLOY_K8S_NAMESPACE "$DEPLOY_K8S_NAMESPACE"
  _k8ssecretname="$_k8snamespace-tls-secret-autogen"

  _savedomainconf DEPLOY_K8S_SA_TOKEN "$DEPLOY_K8S_SA_TOKEN"
  _k8ssatoken="${DEPLOY_K8S_SA_TOKEN}"
  if [ -z "$_k8ssatoken" ]; then
    _err "Kubernetes ServiceAccount token not found. Please define DEPLOY_K8S_SA_TOKEN."
    return 1
  fi
  
  _k8s_endpoint_secret="$_k8sfullurl/api/v1/namespaces/$_k8snamespace/secrets/$_k8ssecretname"
  _k8s_endpoint_secrets="$_k8sfullurl/api/v1/namespaces/$_k8snamespace/secrets"
  _k8s_endpoint_namespace="$_k8sfullurl/api/v1/namespaces/$_k8snamespace"

  # base64 encode the key and fullchain into a single pem and install
  _tlscrt="$(base64 -w 0 "$_cfullchain")"
  _tlskey="$(base64 -w 0 "$_ckey")"
  _secret_payload="{\"apiVersion\":\"v1\",\"data\":{\"tls.crt\":\"$_tlscrt\",\"tls.key\":\"$_tlskey\"},\"kind\":\"Secret\",\"metadata\":{\"name\":\"$_k8ssecretname\",\"namespace\":\"$_k8snamespace\"},\"type\":\"kubernetes.io/tls\"}"
  # _info "tls.crt value is $_tlscrt"
  # _info "tls.key value is $_tlskey"
  # _info "secret payload is $_secret_payload"

  _info "namespace endpoint $_k8s_endpoint_namespace"
  _existing_namespace=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $_k8ssatoken" "$_k8s_endpoint_namespace")
  if [ $_existing_namespace != "200" ]
  then
    _err "Kubernetes namespace, $_k8snamespace, not found ($_existing_namespace). Please make sure the namespace exists."
  fi

  _existing_secret=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $_k8ssatoken" "$_k8s_endpoint_secret")
  if [ $_existing_secret -eq 404 ]
  then
    # create a new secret
    _new_secret=$(curl -s -X POST -H "Content-type: application/json" -H "Authorization: Bearer $_k8ssatoken" "$_k8s_endpoint_secrets" -d "$_secret_payload")
    _info "Created new Secret"
  else
    # patch an existing secret
    _updated_secret=$(curl -s -X PATCH -H "Content-type: application/strategic-merge-patch+json" -H "Authorization: Bearer $_k8ssatoken" "$_k8s_endpoint_secret" -d "$_secret_payload")
    _info "PATCHed existing secret"
  fi

  # restart isn't required after creating a kubernetes resource
  _info "Certificate successfully deployed as kubernetes Secret"
  _info "Success: kubernetes Secret resource created!"

}
