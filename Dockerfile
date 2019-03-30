# docker build -t letsencrypt-automation .
FROM neilpang/acme.sh

# Copy required files, including kubernetes deploy script
COPY requirements requirements
COPY letsencrypt-automation.py /automation/letsencrypt-automation.py
COPY kubernetes.sh /root/.acme.sh/deploy/kubernetes.sh

RUN apk update && apk add python py-pip && pip install --upgrade pip && pip install -r requirements

VOLUME [ "/acme.sh", "/automation/conf" ]

# Create the log file to be able to run tail
RUN echo "*/5 * * * * /usr/bin/python /automation/letsencrypt-automation.py" >> /etc/crontabs/root

# Run the command on container startup
CMD ["/usr/sbin/crond", "-f"]