#!/bin/bash

function print_help {
cat <<EOF
        Postfix Forward Setup Script
===================================================================
Setup postfix to forward email to another server, for example gmail

Required environment variables:

MAIL_HOST
  hostname of your server
  eg mail.example.com
VIRTUAL_ALIAS_DOMAINS
  the domains you want to receive emails for, separated by spaces
  eg example.com mysite.com etcetra.net
VIRTUAL_ALIAS_MAPS
  maping between incoming emails and where to
  forward them. Use @mysite.com for catch all
  emails. Separate multiple rules using ;
  eg me@example.com me@gmail.com;@etcetra.net my-email@gmail.com
SMTP_USERNAME
SMTP_PASSWORD
  authentication for sending mail on behalf on this host
  username should be without domain part, the domain will
  be set to MAIL_HOST


example:
  docker run -d -p 25:25\
  -e MAIL_HOST="mail.example.com"\
  -e VIRTUAL_ALIAS_DOMAINS="example.com"\
  -e VIRTUAL_ALIAS_MAPS="@example.com me@gmail.com"\
  mariusgundersen/postfix-forward

this creates a new smtp server which listens on port 25 and
forwards all email sent to example.com to me@gmail.com
___________________________________________________________________
by Marius Gundersen
EOF
}

if [ -z "$MAIL_HOST" ] || [ -z "$VIRTUAL_ALIAS_DOMAINS" ] || [ -z "$VIRTUAL_ALIAS_MAPS" ]
then
  print_help
  exit 0
fi

echo ">> setting up host and alias"

# add domain
postconf -e myhostname="$MAIL_HOST"
postconf -X mydestination
echo "$MAIL_HOST" > /etc/mailname

#set up virtual domains and adresses
postconf -e virtual_alias_domains="$VIRTUAL_ALIAS_DOMAINS"
postconf -e virtual_alias_maps=hash:/etc/postfix/virtual

# add virtual addresses
IFS=";"
for x in $VIRTUAL_ALIAS_MAPS;
do
  echo "$x" >> /etc/postfix/virtual
done

cat /etc/postfix/virtual

# map virtual addresses
postmap /etc/postfix/virtual

echo ">> setup sasl (authentication of sender)"

useradd -p $(openssl passwd -1 $SMTP_PASSWORD) $SMTP_USERNAME

postconf -e smtpd_sasl_path=smtpd
postconf -e smtpd_sasl_local_domain=
postconf -e smtpd_sasl_auth_enable=yes
postconf -e smtpd_sasl_security_options=noanonymous
postconf -e broken_sasl_auth_clients=yes
postconf -e inet_interfaces=all

echo ">> reducing the amount of spam processed by postfix"
# https://www.howtoforge.com/virtual_postfix_antispam

postconf -e smtpd_helo_required=yes
postconf -e strict_rfc821_envelopes=yes
postconf -e disable_vrfy_command=yes

postconf -e unknown_address_reject_code=554
postconf -e unknown_hostname_reject_code=554
postconf -e unknown_client_reject_code=554


postconf -e smtpd_tls_security_level=may
postconf -e smtpd_tls_auth_only=yes
postconf -e smtp_tls_security_level=may

postconf -e "smtpd_helo_restrictions=\
  permit_mynetworks,\
  reject_non_fqdn_helo_hostname,\
  reject_unknown_helo_hostname,\
  reject_invalid_helo_hostname,\
  permit"

postconf -e "smtpd_recipient_restrictions=\
  permit_sasl_authenticated,\
  reject_invalid_hostname,\
  reject_non_fqdn_hostname,\
  reject_non_fqdn_sender,\
  reject_non_fqdn_recipient,\
  reject_unknown_sender_domain,\
  reject_unknown_recipient_domain,\
  permit_mynetworks,\
  reject_unauth_destination,\
  reject_rbl_client cbl.abuseat.org,\
  reject_rbl_client sbl-xbl.spamhaus.org,\
  reject_rbl_client bl.spamcop.net, \
  reject_rhsbl_sender dsn.rfc-ignorant.org,\
  check_policy_service inet:127.0.0.1:10023,\
  permit"

echo ">> setting up postfix for $MAIL_HOST"

echo ">> Setting postgrey options"

echo 'POSTGREY_OPTS="--inet=127.0.0.1:10023 --delay=60"' > /etc/default/postgray

# starting services
echo ">> starting the services"

service rsyslog start

service saslauthd start

service postgrey start

service postfix start

# print logs
echo ">> printing the logs"
touch /var/log/mail.log /var/log/mail.err /var/log/mail.warn
chmod a+rw /var/log/mail.*
tail -F /var/log/mail.*
