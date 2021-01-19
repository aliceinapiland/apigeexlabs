#!/usr/bin/env bash
source ~/env

task_id="setup-apigeex"
begin_task "${task_id}" "Setting up Apigee X" 30

cd ~

echo "*******************************"
echo "*** (BEGIN) Setup Apigee X  ***"
echo "*******************************"

set -e

if [ -z "$CHILD_PROJECT" ]; then
   echo "ERROR: Environment variable CHILD_PROJECT is not set."
   exit 1
fi

if [ -z "$CHILD_PROJECT_REGION" ]; then
   echo "ERROR: Environment variable CHILD_PROJECT_REGION is not set."
   exit 1
fi

if [ -z "$RUNTIME_HOST_ALIAS" ]; then
   echo "ERROR: Environment variable RUNTIME_HOST_ALIAS is not set."
   exit 1
fi

export NETWORK=default
export SUBNET=default
export MIG=apigee-proxy-group
export MIG_TEMPLATE="${MIG}-template"
export MIG_TEMPLATE_PLACEHOLDER="${MIG}-template-placeholder"

function token { echo -n "$(gcloud config config-helper --force-auth-refresh | grep access_token | grep -o -E '[^ ]+$')" ; }

echo "*** Install gcloud alpha components *** "
gcloud components install alpha --quiet

echo "*** Enable GCP APIs for Apigee X ***"
gcloud services enable \
   apigee.googleapis.com \
   servicenetworking.googleapis.com \
   compute.googleapis.com \
   cloudkms.googleapis.com \
   cloudresourcemanager.googleapis.com \
   --project=$CHILD_PROJECT

echo "*** Configure service networking ***"

echo "****** Define a range of reserved IP addresses for your network. ******"

gcloud compute addresses create google-svcs \
  --description="Peering range for Google services" \
  --global \
  --prefix-length=16 \
  --network=default \
  --purpose=VPC_PEERING \
  --project=$CHILD_PROJECT

echo "*** Connect your project's network to the Service Networking API via VPC peering ***"
gcloud services vpc-peerings connect \
  --service=servicenetworking.googleapis.com \
  --network=default \
  --ranges=google-svcs \
  --project=$CHILD_PROJECT


echo "**** Reserving external IP address for runtime load balancer ****"
gcloud compute addresses create apigee-proxy-external-ip --ip-version=IPV4 --global --project $CHILD_PROJECT
export RUNTIME_IP=$(gcloud compute addresses describe apigee-proxy-external-ip --format="get(address)" --global --project $CHILD_PROJECT)

echo "*** Adding DNS entry for runtime load balancer ***"
add_apigeelabs_dns_entry "A" "${RUNTIME_HOST_ALIAS}." "${RUNTIME_IP}"

echo "*** Creating Google managed cert for runtime load balancer ***"
gcloud compute ssl-certificates create apigee-ssl-cert-managed \
  --description="Certificate for API Traffic" \
  --domains="${RUNTIME_HOST_ALIAS}" \
  --global \
  --project $CHILD_PROJECT


export ENDPOINT=$(gcloud compute instances describe lab-startup --zone ${CHILD_PROJECT_ZONE} --format='value(networkInterfaces.networkIP)')

echo "*** Create a new MIG instance template(ENDPOINT: ${ENDPOINT}) ***"
cat << MIGEOF > apigeex-proxy-startup.sh
#!/bin/sh

endpoint=\$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/attributes/ENDPOINT -H "Metadata-Flavor: Google")

if [ -x /bin/firewall-cmd ]
then
   sysctl -w net.ipv4.ip_forward=1
   firewall-cmd --permanent --add-masquerade
   firewall-cmd --permanent --add-forward-port=port=443:proto=tcp:toaddr="\$endpoint"
   firewall-cmd --add-masquerade
   firewall-cmd --add-forward-port=port=443:proto=tcp:toaddr="\$endpoint"
else
   sysctl -w net.ipv4.ip_forward=1
   iptables -t nat -A POSTROUTING -j MASQUERADE
   iptables -t nat -A PREROUTING -p tcp --dport 443 -j DNAT --to-destination "\$endpoint"
fi

exit 0
MIGEOF

echo "*** Create an instance template ***"
gcloud compute instance-templates create "${MIG_TEMPLATE_PLACEHOLDER}" \
  --region $CHILD_PROJECT_REGION \
  --network $NETWORK \
  --subnet $SUBNET \
  --tags=https-server,apigee-proxy \
  --machine-type n1-standard-1 \
  --image-family centos-7 \
  --image-project centos-cloud \
  --boot-disk-size 20GB \
  --metadata "ENDPOINT=${ENDPOINT}" \
  --metadata-from-file "startup-script=./apigeex-proxy-startup.sh" \
  --project $CHILD_PROJECT

echo "*** Create a managed instance group ***"
gcloud compute instance-groups managed create $MIG \
  --base-instance-name apigee-proxy \
  --size 1 \
  --template "${MIG_TEMPLATE_PLACEHOLDER}" \
  --region $CHILD_PROJECT_REGION \
  --project $CHILD_PROJECT

echo "*** Configure autoscaling for the group ***"
gcloud compute instance-groups managed set-autoscaling $MIG \
  --region $CHILD_PROJECT_REGION \
  --max-num-replicas 20 \
  --target-cpu-utilization 0.75 \
  --cool-down-period 90 \
  --project $CHILD_PROJECT

echo "*** Defined a named port ***"
gcloud compute instance-groups managed set-named-ports $MIG \
  --region $CHILD_PROJECT_REGION \
  --named-ports https:443 \
  --project $CHILD_PROJECT

echo "*** Create a firewall rule that lets the Load Balancer access Apigee Proxy ***"
gcloud compute firewall-rules create k8s-allow-lb-to-apigee-proxy \
  --description "Allow incoming from GLB on TCP port 443 to Apigee Proxy" \
  --network $NETWORK \
  --allow=tcp:443 \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 \
  --target-tags=apigee-proxy \
  --project $CHILD_PROJECT

echo "*** Create a global load balancer ***"

echo "*** Create a health check ***"
gcloud compute health-checks create https hc-apigee-proxy-443 \
  --port 443 \
  --global \
  --request-path /healthz/ingress \
  --project $CHILD_PROJECT

echo "*** Create a backend service called apigee-proxy-backend ***"

gcloud compute backend-services create apigee-proxy-backend \
  --protocol HTTPS \
  --health-checks hc-apigee-proxy-443 \
  --port-name https \
  --timeout 60s \
  --connection-draining-timeout 300s \
  --global \
  --project $CHILD_PROJECT

echo "*** Add the Apigee Proxy instance group to your backend service ***"
gcloud compute backend-services add-backend apigee-proxy-backend \
  --instance-group $MIG \
  --instance-group-region $CHILD_PROJECT_REGION \
  --balancing-mode UTILIZATION \
  --max-utilization 0.8 \
  --global \
  --project $CHILD_PROJECT

echo "*** Create a Load Balancing URL map ***"
gcloud compute url-maps create apigee-proxy-map \
  --default-service apigee-proxy-backend \
  --project $CHILD_PROJECT

echo "*** Create a Load Balancing target HTTPS proxy ***"
gcloud compute target-https-proxies create apigee-https-proxy \
  --url-map apigee-proxy-map \
  --ssl-certificates apigee-ssl-cert-managed \
  --global-ssl-certificates \
  --global \
  --project $CHILD_PROJECT

echo "*** Create a global forwarding rule ***"
gcloud compute forwarding-rules create apigee-proxy-https-lb-rule \
  --address apigee-proxy-external-ip \
  --global \
  --target-https-proxy apigee-https-proxy \
  --ports 443 \
  --project $CHILD_PROJECT


echo "*** Create a new eval org ***"
gcloud alpha apigee organizations provision \
  --runtime-location=$CHILD_PROJECT_REGION \
  --analytics-region=$CHILD_PROJECT_REGION \
  --authorized-network=default \
  --project=$CHILD_PROJECT

echo "*** Update env group ***"
curl --silent -X PATCH https://apigee.googleapis.com/v1/organizations/$CHILD_PROJECT/envgroups/eval-group \
  --header "Authorization: Bearer $(token)" \
  --header 'Content-Type: application/json' \
  --data-raw "{
    \"hostnames\": [
        \"$RUNTIME_HOST_ALIAS\"
    ]
}"

export ENDPOINT=$(
  curl -s -X GET  https://apigee.googleapis.com/v1/organizations/$CHILD_PROJECT/instances/eval-$CHILD_PROJECT_REGION \
    -H "Content-Type:application/json" \
    -H "Authorization: Bearer $(token)" | jq .host --raw-output
)

echo "*** Create a new MIG instance template(ENDPOINT: ${ENDPOINT}) ***"
gcloud compute instance-templates create "${MIG_TEMPLATE}" \
  --region $CHILD_PROJECT_REGION \
  --network $NETWORK \
  --subnet $SUBNET \
  --tags=https-server,apigee-proxy \
  --machine-type n1-standard-1 \
  --image-family centos-7 \
  --image-project centos-cloud \
  --boot-disk-size 20GB \
  --metadata "ENDPOINT=${ENDPOINT}" \
  --metadata-from-file "startup-script=./apigeex-proxy-startup.sh" \
  --project $CHILD_PROJECT

echo "*** Update mig to use new instance template ****"
gcloud compute instance-groups managed set-instance-template "${MIG}" \
  --template "${MIG_TEMPLATE}" \
  --region $CHILD_PROJECT_REGION

echo  "*** Shut down old VMs and bring up new ones ****"
gcloud compute instance-groups managed rolling-action start-update "${MIG}" \
  --version=template="${MIG_TEMPLATE}" \
  --region="${CHILD_PROJECT_REGION}"

end_task "${task_id}"
echo "****************************"
echo "*** (END) Setup Apigee X ***"
echo "****************************"