from string import Template
import json
import os
import requests
import subprocess
import csv
import re
import logging

logging.basicConfig(level=logging.INFO)

class configuration:
    kubernetes = None
    common = None
 
    def __init__(self, config_directory, config_file):
        # load in configuration (directory is assumed relative to this file)
        config_full_path = os.path.join(os.path.dirname(os.path.realpath(__file__)), config_directory, config_file)
        with open(config_full_path, 'r') as myfile:
            configuration_raw = json.load(myfile)
        self.common = configuration_raw['common']
        self.kubernetes = configuration_raw['kubernetes']

# get path to configuration
CONFIG_DIRECTORY = os.getenv('LETSENCRYPT_CONFIG_DIRECTORY', 'conf')
CONFIG_FILE = os.getenv('LETSENCRYPT_CONFIG_FILE', 'letsencrypt-automation.conf.json')
config = configuration(CONFIG_DIRECTORY, CONFIG_FILE)

HEADERS = {"Authorization": "Bearer %s" % config.kubernetes['letsencrypt_serviceaccount_token']}
K8S_API_URI = "https://%s:%s" % (config.kubernetes['api_host'], config.kubernetes['api_port'])
K8S_API_SSL_VERIFY = config.kubernetes['ssl_verify']

K8S_API_TEMPLATE_NAMESPACES = Template('$host/api/v1/namespaces')
K8S_API_TEMPLATE_SECRETS = Template('$host/api/v1/secrets')

def certificate_exists(domain):
    # check for existing certificate; assumes acme.sh installed on host running this script
    acme_sh_list_command_with_arguments = ['acme.sh', '--list', '--listraw']
    result = subprocess.check_output(acme_sh_list_command_with_arguments)
    reader = csv.reader(result.strip().split('\n'), delimiter='|')
    for row in reader:
        # if domain == namespace_tls_domain: break
        if domain == row[0]:
            return True
    return False

def process_tls_certs():
    # get all namespaces
    namespaces_api_url = K8S_API_TEMPLATE_NAMESPACES.substitute(host=K8S_API_URI)
    namespaces_response = requests.get(namespaces_api_url, headers=HEADERS, verify=K8S_API_SSL_VERIFY)
    logging.info('Request for namespaces resulted in %s' % namespaces_response.status_code)
    namespaces_in_response = json.loads(namespaces_response.text)

    if 'items' in namespaces_in_response:
        secrets_api_url = K8S_API_TEMPLATE_SECRETS.substitute(host=K8S_API_URI)
        secrets_response = requests.get(secrets_api_url, headers=HEADERS, verify=K8S_API_SSL_VERIFY)
        secrets_in_response = json.loads(secrets_response.text)
        for current_namespace in namespaces_in_response['items']:
            logging.info('Evaluating namespace "%s" for TLS certificate' % current_namespace['metadata']['name'])
            # check whether this namespace should have a TLS cert
            if 'annotations' in current_namespace['metadata'] \
                and 'namespace_tls_domain' in current_namespace['metadata']['annotations'] \
                and current_namespace['metadata']['annotations']['namespace_tls_domain']:
                logging.info('Processing domain %s for namespace %s' % (current_namespace['metadata']['annotations']['namespace_tls_domain'], current_namespace['metadata']['name']))
                acme_sh_env = os.environ
                if not certificate_exists(current_namespace['metadata']['annotations']['namespace_tls_domain']):
                    # issue a new certificate
                    acme_sh_issue_command_with_arguments = ['acme.sh', '--issue', '--dns', 'dns_nsone', '-d', current_namespace['metadata']['annotations']['namespace_tls_domain']]
                    acme_sh_env["NS1_Key"] = config.common["ns1_key"]
                    if config.common['acme_sh_test']:
                        acme_sh_issue_command_with_arguments.append('--test')
                    result = subprocess.check_output(acme_sh_issue_command_with_arguments, env=acme_sh_env)
                    print result
                    # fullchain_path = re.findall( r'full chain.*:\s*(.*\.cer)', result, re.M)[0]
                    # key_path = re.findall( r'key is in\s*(.*\.key)', result, re.M)[0]
                    # print fullchain_path
                    # print key_path

                for current_secret in secrets_in_response['items']:
                    if current_secret['metadata']['namespace'] == current_namespace['metadata']['name']:
                        if 'tls-secret-autogen' in current_secret['metadata']['name']:
                            continue

                # deploy the new certificate
                acme_sh_deploy_command_with_arguments = ['acme.sh', '--deploy', '--deploy-hook', 'kubernetes', '-d', current_namespace['metadata']['annotations']['namespace_tls_domain']]
                acme_sh_env["DEPLOY_K8S_URL"] = config.kubernetes['api_host']
                acme_sh_env["DEPLOY_K8S_PORT"] = config.kubernetes['api_port']
                acme_sh_env["DEPLOY_K8S_NAMESPACE"] = current_namespace['metadata']['name']
                acme_sh_env["DEPLOY_K8S_SA_TOKEN"] = config.kubernetes['letsencrypt_serviceaccount_token']
                result = subprocess.check_output(acme_sh_deploy_command_with_arguments, env=acme_sh_env)
                print result

if __name__ == '__main__':
    process_tls_certs()
