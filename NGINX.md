# NGINX


NGINX is a light-yet-powerful HTTP server that can also be used as a reverse/forward proxy for the administration and balancing of internet traffic. It's a popular app and a lot of websites online use it. That being said, I decided on using it to primarily serve my websites (and related traffic) with on the web. For my particular set-up, I have a variety of machines within my internal network that all point to a single reverse proxy (NGINX) within LAN. This reverse proxy then connects to my VPS through a VPN tunnel. With some iptables magic, I'm able to serve some of my services and sites out to the web.

As nifty as this is, there are some inherent limitations to keep in mind that I've faced personally. The main limitation is that any and all traffic going through the VPN tunnel has been masqueraded to be read as my VPN's IP and not as the client's IP (of whom is connecting to my services). This is annoying, given that I need that client IP info if I want to have accurate logs or if I wanted to have an IDS like fail2ban to work properly. Of course, I could just host my services on a VPS or three and call it a day, where there wouldn't be any need for masquerading in the first place...

That costs more money, though. And boy, am I stubborn about that (lol). This stubbornness has paid off in letting me find out how to maintain my set-up (and retain some savings in the meanwhile). Hopefully these notes can help someone else out (like, you, the reader!) if they want to imitate a similar set-up.

To preface, I'm not a super security expert or anything like that. It's about as much of a learning process for me as it is for any other beginners and I mostly stick to best practices + erring on the side of general paranoia. That being said, I won't speak so-much on the security side of things more than I will speak on what I like and dislike of the ways of going about how to set-up NGINX.

On the security front, I assume that:
- You follow best practices (access controls, running services as non-root user where possible, complex alphanumeric passwords, etc)
- You harden your servers where possible (unattended-upgrades, scheduled updates, remove unnecessary services/software on a machine that doesn't need it, firewalling)
- You utilize software to aid in security where it makes sense (SELinux, AppArmor, fail2ban, log monitoring software of your choice)

Likewise, this tutorial assumes that you have some degree of general understanding with hosting webservers with NGINX, mainly in actually getting a webpage up and how to enable SSL with NGINX as well (manually, with certbot or your choice of preference).

## Methods and my likes/dislikes

Before I discovered the potential of NGINX, what I ended up doing was port-forwarding port 80 and 443 on my reverse proxy through to my VPS. This is convenient and neat but there's an issue with IP obfuscation that's present throughout the application. This is mainly due to the `MASQUERADE` rule used within iptables to change the IP from an incoming client to one that can traverse across my VPN and to my proxy. The content still is served properly but it makes certain IDS systems (like fail2ban) not work, as logs will only show the IP of the WG gateway. The same goes for any and all logs for items and services where logging client connections for security is necessary. Not ideal.

Thankfully, NGINX has ways to go around that to where you can still get that information even with the kind of set-up that I have. There's two main methods that I've found works for setting up NGINX to serve content on the web with:
- NGINX Proxy Pass from server to VPS
- NGINX Stream Module for VPS (my preferred method)

#### Proxy Pass
- Likes
	- Generally straightforward to set-up
	- Dynamic DNS doesn't get in the way of serving content
	- General obfuscation of home address of where content is served from

- Dislikes
	- Have to install WG and set up a peer on every device that's serving content
	- Better for a single-device or maybe two. Multiple devices can cause disorganization and potential hiccups/confusion to crop up when issues arise with regards to networking, routing, troubleshooting, etc.
	- Potential port-forwarding can occur still (loss of client IP information)
	- SSL certs are not within LAN
	- If using non-nginx webserver, sending IP header information requires knowledge of other webservers

#### Stream Module
- Likes
	- Only have to install WG on one device, all internal servers face internal traffic only
	- SSL certs sit on a device behind LAN
	- Non-HTTP(S) traffic can be routed through it too (no port forwarding)
	- Dynamic DNS doesn't get in the way of serving content
	- Additional obfuscation of home address of where content is served from
	- Easy (lazy) SSL within LAN if you have an internal DNS that can point to your proxy

- Dislikes
	- Parsing through a lot of documentation
	- For proper security, you'd need a dedicated machine (ideally a low-powered SBC with a GB NIC)
	- Additional items pending...

With that being said, I'll begin with how one goes about setting up either system.

## PROYX PASS

### How does it work?
Nginx works as a reverse proxy through the use of its `proxy_pass` module, which, in a location block, will tell it where to pull content from. For the sake of this tutorial, I won't go into the options necessary to get this working for individual applications, webpages, etc, I'm simply covering the set-up for distributing content to the web with.

In this set-up, we have NGINX installed on our VPS with listening ports open on 80 and 443. For our internal servers that serve the content, we will need to have Wireguard installed on them all, so that they can all act as peers within the VPN.

For our internal server or servers, we would assign them IP addresses within the VPN. Let's say they're all X.X.X.0/24 and such. So we have our gateway (VPS) at X.X.X.1, webserver 1 at X.X.X.2, and webserver 2 at X.X.X.3. With our webservers hosting content, we would then go to the NGINX config within our VPS and set the `proxy_pass` option to point to our webservers:
```
proxy_pass http://X.X.X.2:80;
proxy_pass http://X.X.X.3:80;
```

From here, through our VPN connection, the NGINX reverse proxy on the VPS can capture client information and serve content for us while also communicating with our servers behind LAN.

### Dependencies
This tutorial assumes that you've already got your webservers up and going with whatever webserver application of your choice (Apache, NGINX, etc). You'll need to install Wireguard on all systems and also NGINX on the VPS if you haven't already. I have the dependencies set to install the full suite of NGINX modules for simplicity's sake but it _is_ best practice to build NGINX only with what you need.

NGINX:

Debian/Ubuntu: `apt install nginx-full`

RHEL/Fedora: `dnf install nginx-all-modules`


Wireguard:

Debian/Ubuntu: `apt install wireguard`

RHEL/Fedora: `dnf install wireguard-tools`

### Wireguard

See my Wireguard notes [here.](Wireguard.md)

### NGINX

Before moving any further, make sure that your web servers are reachable on standard port 80 for HTTP traffic (or whatever port you assigned to it to serve traffic on).

On your VPS, within your NGINX config, when defining a server block and a `proxy_pass` parameter, be sure to have it point to your webserver's WG IP within the VPN. From the section from earlier, this should look something like:
```
proxy_pass http://X.X.X.2:80;
```

Following this, you should also have this header information set within the `location` block as well:
```
proxy_set_header X-Real-IP $remote_addr;
```

You also will need to set a parameter in your `nginx.conf` file to allow it to set the proper IP header information from the WG tunnel. This would be put into your `http` block like this:
```
set_real_ip_from <WG.Gateway.IP.From-VPS>
```

Have your VPS listen on 80, 443, the works and restart NGINX. Your VPS should now be proxying traffic to your webservers within your LAN. Apply SSL certs as needed by your option of choice (I like using certbot).


## STREAM MODULE

#### How does it work?
NGINX has a module that's not built by default known as `ngx_stream_core_module`. This module is what allows NGINX to have the capability of handling non-http/https traffic. This means that NGINX could handle generic protocols like DNS, SMTP and otherwise. For my purposes, I'll only have it act as a relay for HTTP/HTTPS traffic, as I want it to be able to pass client IP header info over to my reverse proxy within LAN.

The set-up would then end up having an NGINX host on the VPS and within LAN. The LAN host will be our reverse proxy and the VPS host will be our relay. When traffic hits the VPS, it won't terminate TLS/SSL packets at the VPS. Rather, it will forward the traffic (with all of the relevant information, client info) to our reverse proxy within LAN. This is done through a WG tunnel, of course. From there, when the reverse proxy receives the traffic, the TLS/SSL packets can terminate there and the server can do its work as necessary.

The connectivity for this is similar to the last method, where we'd have WG installed on our VPS and on our reverse proxy within our LAN. The main difference is that there'd only be two devices in use, so the CIDR of the addresses could be made to only include one (instead of the full 255).
```
Gateway: X.X.X.1/32
Peer: X.X.X.2/32
```

### Dependencies

NGINX:
Debian/Ubuntu: `apt install nginx-full`

RHEL/Fedora: `dnf install nginx-all-modules`

Wireguard:
Debian/Ubuntu: `apt install wireguard`

RHEL/Fedora: `dnf install wireguard-tools`

If you aren't sure that the stream module is installed or you've installed NGINX some other way with other modules, the dependency for that is:

Debian/Ubuntu: `libnginx-mod-stream`

RHEL/Fedora: `nginx-mod-stream`

Stream must be installed BOTH on the VPS and your reverse proxy.

###Wireguard

General set-up instructions [here.](Wireguard.md)

### NGINX

#### VPS Configuration
Go to `/etc/nginx/nginx.conf` and define a new block in the config (above or below the `http` block, doesn't matter). Name this block `stream`. In there, you'll want to create another two blocks and define it as `upstream`. This will be our identifier for our reverse proxy within our LAN that'll be connected to through WG. When this is defined, you will create individual `server` blocks for which NGINX on the VPS will listen on.
```
stream {  
  
   upstream proxyhttps {  
       #points to proxy within LAN for HTTPS traffic  
       server your.wg.ip.here:4430; # alternate proxy protocol port (so lan keeps 443 SSL internally)  
   }  
  
   upstream proxyhttp {  
       #points to proxy within LAN for HTTP traffic  
       server your.wg.ip.here:4480;  
   }  
  
   server {
	#frontend for VPS to send stuff back to LAN proxy (HTTP)
       listen 80;  
       proxy_pass proxyhttp;  
       proxy_protocol on;  
   }  
  
   server {  
       #frontend for VPS to send stuff back to LAN proxy (HTTPS)
       listen 443;  
       proxy_pass proxyhttps;  
       ssl_preread on;  
       proxy_protocol on;  
   }  
}
```

The config here may seem convoluted. There is a method to the madness here, trust me. First, we define two upstreams for our reverse proxy behind LAN. These ports are set to be non-standard, as HTTP will throw a 400 error and HTTPS will not route properly otherwise. Having HTTPS route to a different port also gives us the benefit of easy SSL certs within LAN, so there's another reason to maintain this consistency.

With our upstreams defined, we now create two servers, one for each port. This tells our VPS to listen on port 80 and 443 for traffic to route back to our reverse proxy on ports 4430 and 4480. You will want these in separate server blocks, primarily because having HTTP in the same block where `ssl_preread` is defined will give you a 400 error as well. 

Don't forget to set a parameter in your `nginx.conf` file to allow it to set the proper IP header information from the WG tunnel. This would be put into your `http` block like this:
```
set_real_ip_from <WG.Gateway.IP.From-VPS>
```

Verify that your firewall rules are set, ensure that NGINX isn't already using ports 80, 443 and give it a restart. Your VPS should now be routing traffic from those ports to ports 4430/4480 on your reverse proxy.

### Reverse Proxy Configuration
In your NGINX configuration on the proxy, you will need to add additional listen ports to your servers. Where your server would normally listen on 80/443, you will need to add additional listening ports.
```
listen 4480 proxy_protocol;
listen 4430 ssl http2 proxy_protocol;
```

These ports are our alternative 80/443 ports from our VPS to route our traffic over the WG tunnel. You can add them next to your standard ports and save your config after the fact. Note that if you use certbot to get SSL certs from, you'll need to go back in and add your SSL proxy pass port on top of 443 for it to connect properly (not an automatic thing).

Check your settings, restart NGINX and you should now be able to access your webpages and services.

### TO-DO:
- NGINX Stream for other traffic
- Clean-up in the future
- Drawings, diagrams for visual aid
- Sources
