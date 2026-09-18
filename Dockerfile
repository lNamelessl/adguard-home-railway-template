FROM adguard/adguardhome:v0.107.79

COPY entrypoint.sh /opt/adguardhome/entrypoint.sh
RUN chmod +x /opt/adguardhome/entrypoint.sh

ENTRYPOINT ["/bin/sh", "/opt/adguardhome/entrypoint.sh"]
