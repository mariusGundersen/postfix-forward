FROM ubuntu

RUN echo mail > /etc/hostname

# install
ENV DEBIAN_FRONTEND non-interactive
RUN apt-get update; apt-get install -y postfix postgrey sasl2-bin

# Fix for https://stackoverflow.com/questions/56609182/openthread-environment-docker-rsyslogd-imklog-cannot-open-kernel-log-proc-km/60265997#60265997
RUN sed -i '/imklog/s/^/#/' /etc/rsyslog.conf

EXPOSE 25
EXPOSE 587

# Add startup script
ADD startup.sh /opt/startup.sh
RUN chmod a+x /opt/startup.sh

ADD saslauthd /etc/default/saslauthd
ADD sasl/smtpd.conf /etc/postfix/sasl/smtpd.conf

RUN rm -r /var/run/saslauthd/ \
  && mkdir -p /var/spool/postfix/var/run/saslauthd \
  && ln -s /var/spool/postfix/var/run/saslauthd /var/run \
  && chgrp sasl /var/spool/postfix/var/run/saslauthd \
  && adduser postfix sasl

# Docker startup
ENTRYPOINT ["/opt/startup.sh"]
