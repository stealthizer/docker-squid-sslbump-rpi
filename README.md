docker-squid-sslbump-rpi
======================
Squid SSL proxy with SSL bumping and content filtering for Docker. Supports transparent and non-transparent proxy modes with YouTube Shorts blocking capabilities.

Based on syakesaba/docker-sslbump-proxy.

Baseimage
======================
Debian Trixie (multistage build for optimized size)

⚠️ Legal Disclaimer
======================
**WARNING: Traffic interception may be illegal in your country or jurisdiction.**

This software performs SSL/TLS traffic interception (SSL bumping) which may be subject to legal restrictions depending on:
- Your country's laws regarding electronic communications and privacy
- Your network's terms of service
- Local regulations on cryptographic interception
- Employment and workplace monitoring laws

**Use this software only:**
- On networks you own or have explicit authorization to monitor
- For educational and learning purposes on your own devices
- With informed consent from all users whose traffic will be intercepted
- In compliance with all applicable laws and regulations

The authors are not responsible for any misuse or legal consequences resulting from the use of this software.

Usage - Blocking YouTube Shorts
======================

### Quick Start (Transparent + Non-Transparent Mode)

```sh
git clone https://github.com/justinschw/docker-squid-sslbump-rpi.git
cd docker-squid-sslbump-rpi

# Build the image
docker build . -t docker-squid-sslbump-slim:latest

# Run with both transparent and non-transparent proxy modes enabled
docker run -d \
    --name squid \
    --restart=always \
    -v $(pwd)/ssl:/usr/local/squid/ssl \
    -v $(pwd)/logs:/usr/local/squid/var/logs:rw \
    -v $(pwd)/etc:/usr/local/squid/etc:rw \
    -p 3128:3128 \
    -p 3130:3130 \
    -p 3131:3131 \
    -e TRANSPARENT=1 \
    --cap-add=NET_ADMIN \
    docker-squid-sslbump-slim:latest
```

### Port Mappings

- **3128**: Standard HTTP/HTTPS proxy port (SSL bump enabled)
- **3130**: Alternate proxy port (if configured)
- **3131**: Transparent HTTPS interception port

### Volume Mappings

- `./ssl`: SSL certificates directory (contains CA cert and key for SSL bumping)
- `./logs`: Squid access and cache logs
- `./etc`: Squid configuration files (squid.conf)

### Environment Variables

- `TRANSPARENT=1`: Enables transparent proxy mode with iptables rules

### Certificate Setup

Pick your CA certificate and import it into your web browsers and devices:

**Certificate location**: `./ssl/bluestar.crt` (or `/usr/local/squid/ssl/bluestar.crt` inside container)

To use the proxy:

1. **Non-transparent mode**: Configure your browser/device to use `<host-ip>:3128` as HTTP/HTTPS proxy
2. **Transparent mode**: Route traffic through the host machine using iptables/routing rules (see below)
3. **Import the CA certificate** into your browser's trusted root certificates

Usage (Transparent Proxy)
======================

When using transparent mode (`TRANSPARENT=1`), you need to redirect traffic from your network to the proxy. Example iptables rules on your router/gateway:

```sh
# Redirect HTTP traffic
iptables -t nat -A PREROUTING -i br0 -p tcp --dport 80 -j DNAT --to <squid-host>:3128

# Redirect HTTPS traffic to transparent port
iptables -t nat -A PREROUTING -i br0 -p tcp --dport 443 -j DNAT --to <squid-host>:3131
```

Replace `br0` with your LAN interface and `<squid-host>` with the IP address of the machine running Squid. 

Technical Deep Dive - SSL Bumping and YouTube Shorts Blocking
======================

### How SSL Bumping Works

SSL/TLS encryption normally prevents proxies from inspecting HTTPS traffic. SSL bumping (also called SSL interception or MITM proxying) solves this by:

1. **Client Connection**: When a client attempts to connect to an HTTPS site (e.g., youtube.com), the proxy intercepts the connection
2. **Certificate Generation**: Squid dynamically generates a fake SSL certificate for the destination domain, signed by its own CA certificate
3. **Dual TLS Connections**:
   - The proxy establishes a TLS connection with the client using the fake certificate
   - Simultaneously, it establishes a separate TLS connection with the real destination server
4. **Traffic Inspection**: The proxy can now decrypt, inspect, and modify the traffic in both directions
5. **Content Filtering**: Based on configured rules, Squid can block, allow, or modify requests

### Why SSL Bumping is Required for YouTube Shorts

YouTube Shorts operates entirely over HTTPS, making the URLs, API calls, and request parameters invisible to traditional proxies. Without SSL bumping:

- Shorts URLs like `https://youtube.com/shorts/xyz` are encrypted
- API endpoints like `/youtubei/v1/reel/` are invisible
- HTTP headers containing `Referer: /shorts/` cannot be inspected

SSL bumping exposes this encrypted traffic, allowing granular content filtering.

### Configuration Components for Shorts Blocking

#### 1. SSL Bump Configuration (squid.conf:40-56)

```
sslcrtd_program /usr/local/squid/libexec/security_file_certgen -s /usr/local/squid/var/lib/ssl_db -M 4MB
ssl_bump peek step1 all
ssl_bump bump step2 youtube_domain
ssl_bump splice step2 all
ssl_bump bump step3
```

- **sslcrtd_program**: Certificate generator daemon that creates fake certificates on-the-fly
- **peek step1**: Peek at SNI (Server Name Indication) without bumping yet
- **bump step2 youtube_domain**: Force bumping for YouTube domains to inspect all traffic
- **splice step2 all**: Splice (pass-through without inspection) for non-YouTube domains to improve performance
- **bump step3**: Complete the bumping handshake

This selective bumping strategy only inspects YouTube traffic, reducing CPU load.

#### 2. ACL Definitions (squid.conf:26-37)

Multiple ACLs target different aspects of YouTube Shorts:

```
acl youtube_shorts url_regex -i youtube\.com/shorts
acl youtube_shorts_path urlpath_regex -i /shorts
acl youtube_shorts_reel url_regex -i /youtubei/v1/reel/
acl youtube_shorts_api url_regex -i reel_watch_sequence
acl youtube_shorts_item url_regex -i reel_item_watch
acl shorts_video_params url_regex -i [?&]shorts=
acl shorts_referer_header req_header Referer -i /shorts/
```

- **URL patterns**: Match Shorts URLs in the request path
- **API endpoints**: Block the backend API calls that load Shorts content (`/youtubei/v1/reel/`)
- **Referer headers**: Block requests with Shorts pages in the Referer, preventing embedded content from loading

#### 3. Access Control Rules (squid.conf:62-70)

```
http_access deny youtube_shorts
http_access deny youtube_shorts_reel
http_access deny youtube_shorts_api
http_access deny shorts_referer_header
http_access deny googlevideo_domain shorts_referer_header
```

These rules deny access when ACL patterns match. The multi-layered approach ensures:
- Direct Shorts URLs are blocked
- Shorts API calls fail even if the page loads
- Video streams from `googlevideo.com` are blocked when requested from Shorts pages

#### 4. Transparent Proxy Setup

The `TRANSPARENT=1` environment variable triggers iptables configuration in `entrypoint.sh`:

```sh
iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-ports 3128
iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-ports 3131
```

- Port 3131 is configured with `intercept` mode in squid.conf
- This allows transparent HTTPS interception without client configuration
- Requires `--cap-add=NET_ADMIN` capability to modify iptables rules

### Why Multiple Blocking Rules are Necessary

YouTube Shorts uses several loading mechanisms:

1. **Direct URL access**: `youtube.com/shorts/VideoID`
2. **Embedded API calls**: JavaScript dynamically loads Shorts via API endpoints
3. **Progressive web app**: Shorts can load through in-page navigation without full URL changes
4. **Video delivery**: Actual video streams come from `googlevideo.com` CDN

A single URL regex wouldn't catch all these mechanisms. The comprehensive ACL list ensures blocking at multiple layers:

- **URL layer**: Catches direct navigation
- **API layer**: Prevents JavaScript from loading Shorts data
- **Header layer**: Blocks related resources even when URLs don't contain "shorts"
- **CDN layer**: Prevents video playback even if API calls succeed

### Certificate Trust Requirement

For SSL bumping to work seamlessly:

1. The Squid CA certificate (`ssl/bluestar.crt`) must be installed on all client devices
2. Browsers/OS must trust this certificate as a root CA
3. Without this trust, browsers will show certificate warnings for all HTTPS sites

This is why SSL interception requires control over the client devices.

### Performance and Security Considerations

- **Selective bumping**: Only YouTube is bumped; other sites are spliced for better performance
- **Certificate caching**: 4MB dynamic certificate cache reduces regeneration overhead
- **Security trade-off**: SSL bumping inherently weakens end-to-end encryption
- **Log everything**: Access logs in `./logs/access.log` show all blocked requests for debugging

Security Notes
======================
Make sure your proxy is secure:
- Protect the CA private key (`ssl/bluestar.pem`) - anyone with this can impersonate any website
- Apply firewall rules to restrict proxy access to trusted networks only
- Consider using Squid ACLs to restrict which clients can use the proxy
- Regularly review access logs for unauthorized usage
- Keep Squid updated to patch security vulnerabilities

See: entrypoint.sh for transparent mode iptables configuration

License
======================
MIT License  
See: LICENSE

