docker-squid-sslbump-rpi
======================
squid ssl proxy with icap for docker on raspberry pi. Based on syakesaba/docker-sslbump-proxy.

Baseimage
======================
raspbian/stretch

Usage
======================
```sh
git clone https://github.com/justinschw/docker-squid-sslbump-rpi.git
cd docker-squid-sslbump-rpi
docker build . -t docker-squid-sslbump-rpi
docker run -ti -p 3128:3128 docker-squid-sslbump-rpi
#C-p q to detach, or
#docker run -d -p 3128:3128 docker-squid-sslbump-rpi

# For transparent proxy mode (requires NET_ADMIN capability):
docker run -d -p 3128:3128 -p 3131:3131 --cap-add=NET_ADMIN -e TRANSPARENT=1 docker-squid-sslbump-rpi
```

Usage (Proxy)
======================
Pick your fakeroot-cert and import it into your web browsers.  
FILE PATH: /usr/local/squid/myCA.der  
or normally access some HTTPS webpages and "Trust Cert". 

Note
======================
Make sure your proxy safe.  
To prevent unwanted use, firewalls or some squid-acls should be applied.  
See: entrypoint.sh

License
======================
MIT License  
See: LICENSE

