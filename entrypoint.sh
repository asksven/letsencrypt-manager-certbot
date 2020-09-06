#!/bin/sh

if [[ -z $EMAIL || -z $DOMAINS || -z $SECRET || -z $DEPLOYMENT ]]; then
	echo "EMAIL, DOMAINS, SECERT, and DEPLOYMENT env vars required"
	exit 1
fi

NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)

OPTION=""
COMMAND="certonly"

echo "Checking cert state"
certbot certificates --config-dir /letsencrypt

if [ $TEST_CERT == "1" ]; then
    OPTION="--test-cert"
fi

cd $HOME
python -m http.server 80 &
PID=$!

if [ $RENEW == "1" ]; then
    echo "Running: certbot renew --config-dir /letsencrypt"
    certbot renew --config-dir /letsencrypt
    if [ $? -eq 0 ]; then
        echo "Nothing to renew"
        kill $PID
        exit 0
    fi
else
    echo "Running: certbot --config-dir /letsencrypt $COMMAND $OPTION --webroot -w $HOME -n --agree-tos --email ${EMAIL} --no-self-upgrade -d ${DOMAINS}"
    certbot certonly --config-dir /letsencrypt $OPTION --webroot -w $HOME -n --agree-tos --email ${EMAIL} --no-self-upgrade -d ${DOMAINS}
fi

kill $PID

CERTPATH=/letsencrypt/live/$(echo $DOMAINS | cut -f1 -d',')

echo "checking state"
ls -laR /letsencrypt

ls $CERTPATH || exit 1

cat /secret-patch-template.json | \
	sed "s/NAMESPACE/${NAMESPACE}/" | \
	sed "s/NAME/${SECRET}/" | \
	sed "s/TLSCERT/$(cat ${CERTPATH}/fullchain.pem | base64 | tr -d '\n')/" | \
	sed "s/TLSKEY/$(cat ${CERTPATH}/privkey.pem |  base64 | tr -d '\n')/" \
	> /secret-patch.json

ls /secret-patch.json || exit 1

# update secret

curl -v --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" -k -v -XPATCH  -H "Accept: application/json, */*" -H "Content-Type: application/strategic-merge-patch+json" -d @/secret-patch.json https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT_HTTPS/api/v1/namespaces/${NAMESPACE}/secrets/${SECRET}

cat /deployment-patch-template.json | \
	sed "s/TLSUPDATED/$(date)/" | \
	sed "s/NAMESPACE/${NAMESPACE}/" | \
	sed "s/NAME/${DEPLOYMENT}/" \
	> /deployment-patch.json

ls /deployment-patch.json || exit 1

# update pod spec on ingress deployment to trigger redeploy
curl -v --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" -k -v -XPATCH  -H "Accept: application/json, */*" -H "Content-Type: application/strategic-merge-patch+json" -d @/deployment-patch.json https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT_HTTPS/apis/extensions/v1beta1/namespaces/${NAMESPACE}/deployments/${DEPLOYMENT}