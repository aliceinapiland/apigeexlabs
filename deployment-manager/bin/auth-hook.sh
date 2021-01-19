#!/bin/bash
exec 1> >(logger -t $(basename $0))
exec 2> >(logger -s -t $(basename $0))


source ~/env

export CHALLENGE_PREFIX="_acme-challenge"

add_apigeelabs_dns_entry "TXT" "${CHALLENGE_PREFIX}.${CERTBOT_DOMAIN}"  "${CERTBOT_VALIDATION}" "1"
wait_for_apigeelabs_dns_record "TXT" "${CHALLENGE_PREFIX}.${CERTBOT_DOMAIN}" "${AUTHORITATIVE_NAMESERVER}"
echo "Sleeping for 30 seconds as buffer ..."
sleep 30; # sleep extra time for good measure ...
