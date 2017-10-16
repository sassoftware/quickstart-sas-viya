#!/bin/sh
#right now this has to be run on the same machine as the log with the reset link - but if http proxy is on another machine this will need to be updated

export host=localhost
export password=${1:-lnxsas}

export code=$(ls -tr /var/log/sas/viya/saslogon/default/sas-saslogon_* | tail -n1 | grep '.log$' | xargs grep 'sasboot' | cut -d'=' -f2)
# make the first request, this expends the link
curl http://$host/SASLogon/reset_password?code=$code -c cookies -o output
# get a few things out of the output to use in the next request
export CSRF_TOKEN=`grep 'name="_csrf"' output | cut -f 6 -d '"'`
export NEW_CODE=`grep 'name="code"' output | cut -f 6 -d '"'`
# make the second request with the password and other information 
curl -b cookies http://$host/SASLogon/reset_password.do -H "Content-Type: application/x-www-form-urlencoded" -d "code=${NEW_CODE}&email=none&password=${password}&password_confirmation=${password}&_csrf=${CSRF_TOKEN}"

