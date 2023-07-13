# Wireguard
Wireguard (referred to as WG from hereon) is a P2P connection protocol that securely tunnels internet traffic from one point to another. It can be used to connect two peers together, more than 3 peers together and even have a number of peers all connect to a single endpoint. In essence, it's just an app to facilitate encrypted P2P traffic with the benefit of it working as a VPN server/service if one would so desire it to be.

WG is written in C and is native to the Linux kernel since version 5.6. Further documentation for the app can be found here: https://github.com/pirate/wireguard-docs

For our instance, we will want to deploy WG as a solution to tunnel self-hosted services beyond the LAN to a public-facing endpoint.

  ![Screenshot from 2023-01-05 18-31-46](https://user-images.githubusercontent.com/93142187/230627411-e88e56a3-016d-401d-81df-6259d69a5639.png)

This design was conceptualized from my earlier SSH tunneling efforts and from this reddit post describing the process here: https://www.reddit.com/r/selfhosted/comments/mey3yp/reverse_proxy_on_vps_through_wireguard_tunnel_or/

TL;DR: Yes, it is doable.

Things that I like about this design:
- Only one device needs to expose itself to outside internet
- Proxy can simply be a minimal service, locked-down box only hosting Apache/NGINX/Proxy-of-your-choice
- Proxy only existing on one system makes for neater organizing (or centralization) of SSL certs

Things that might be an issue with the design:
- Might be harder to forward client IP's through this set-up

## *Installation*

First and foremost, the set-up on our systems, both the proxy and the VPS. Some tools that we'd want to make sure we have is `net-tools` for diagnosing connections as necessary. Otherwise, install Wireguard onto both systems using your package manager. Here's some common ones with their related packages:

Debian:
`apt install wireguard`

Fedora:
`dnf install wireguard-tools`

Arch:
`pacman -S wireguard-tools`

Other installation options can be found here: https://www.wireguard.com/install/

Depending on the version of Linux, you may need to ensure that you have the WG kernel modules installed as well. Beyond Linux 5.6, they're included in the kernel, but anyhthing older than that will require those. You can install them with your package manager. The modules are usually labeled as `wireguard-dkms`

Also be sure to have `iptables` installed on the system too.

## _Configuration_

##### wg.conf (Client)

WG may typically create a configuration file at `/etc/wireguard/wg0.conf`. If it isn't there, then add it. This is where we'll set up our connections between our peers. For the purpose of my specific usecase, we're setting up a peer to be a "VPN Server" in essence. Referring to the drawn chart above, the box labeled as the proxy server will be referred to as the "client" and the VPS will be labeled as the "host."

An addendum, the way we're configuring our VPS Server is referred to as a "Bounce Server" in the WG config documentation.

Your WG client's configuration should appear as such:
```
[Interface]
# private interface for this device
Address = <enter in a IP address to use to access the VPN with, typically with a CIDR of /32>
# private key for device
PrivateKey = <CLIENT privatekey goes here>
# OPTIONAL: ListenPort = <define a port to establish connections with>

[Peer]
#information about device on the other end
#pubkey of the server should go here
PublicKey = <SERVER publickey goes here>
#IP of the server host
Endpoint = <IP of server here. If you specified a specific port for the connection to join onto, annotate  it with <ip>:<port> >
#comment pending
AllowedIPs = <your range here>
```

[Interface] defines the IP of which our client here will be connecting to the host with. Because we are only connecting one client (that being our reverse proxy), we'll assign an IP to it with a CIDR of /32. The IP can be anything that you want, meaning, you define a IP range of which your VPN subnet will connect to. For this example, I'll be making mine `10.0.10.2/32`

```
Address = 10.0.10.2/32
```

For our client and host to securely communicate with each other, we will need to create keypairs for the two to communicate with. This can be done by generateing a private key and a public key from said private key with a command that WG provides us with:
```
wg genkey | tee privatekey | wg pubkey > publickey
```
This prints out two files: _publickey_ and _privatekey_. We will want to take our _privatekey_ and set it to `PrivateKey` in the config. 

For a strongly firewalled circumstance where, say, in a iptables configuration with the OUTPUT table's policy set to DROP, you'll want to add in a `ListenPort` field. This will allow the server to communicate with the endpoint after defining a sport rule on the output table.

Thus concludes the config for our client's [Interface].

[Peer] defines that of which we are connecting to. As explained in the name, it defines a connection or number of connections you would want to make to other clients in the WG network. For this to work properly we'll need to run that `wg genkey` command on our host to generate a keypair there. The public key that's generated from that will be put into our `PublicKey` field.

`Endpoint` is just the public IP of our server. If you have a specific port that you want to specify for it, annotate it within the IP itself (if that's the right terminology idk, it's in the example up there).

`AllowedIPs` is the defined range of which the peer (client system!) will route traffic to. For more simple situations, this is just the IP of the connected client within the P2P connection. For our situation here with our bounce server, we'll define an IP range with a CIDR of /24
```
AllowedIPs = 10.0.10.0/24
```
This creates a range of 255 addresses of which traffic can be routed to from within the VPN.

That should conclude our configuration for our .conf file.

##### Routing (Client) aka: "Just In Case"

Pending on whether or not this is necessary since I had a fringe case of "Wow I Sure Did Mess That One Up"

That and `wg-quick` should take care of that if everything's all set up properly.

If not, you can manually add a route by inputting:
```
ip route add 10.0.10.0/24 dev wg0
```
This is set to be configured to my particular VPN address space

You will also need to manually add in the connections to `ip` for the interface too if `wg-quick` fails to work.
```
ip link add dev wg0 type wireguard
ip address add dev wg0 10.0.10.2/24
```
This manually creates an interface named "wg0" and assigns it the desired IP address that you want.

Also be sure to save the configuration settings too if not done (with `wg setconf`)
```
wg setconf wg0 /etc/wireguard/wg0.conf
```

Afterwards you can throw the connection up with:
`ip link set up dev wg0`
And it can be taken down by replacing `up` with `down`


##### Connecting (Client)

Connecting to the endpoint should be as simple as running this command:
```
wg-quick up wg0
```
addendum, if you want to take the interface down, just run that command but replace "up" with "down"

If you run `ip a` you should see a `wg0` in your list of connections. The same should be true for a new connection being in your route table in `ip route`

This concludes set-up on the client.

##### wg.conf (Server)

```
[Interface]
#Address of this particular instance, even if it IS a server. You can have the CIDR be more open here (usually /24)
Address = 
#To save configuration with. You'll want this to typically be true.
SaveConfig = true 
#routing config
#reoplace <interface> with what's listening to internet connections
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o <interface> -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o <interface> -j MASQUERADE
#the port of which the server should listen on. this should be set in the client's endpoint setting
ListenPort = <SERVER port>
PrivateKey = <SERVER privatekey>

#clients who will connect to this server, or rather, a specific instance
#if you want more peers, you add more [Peer] categories
#For this instance, we will only have one
[Peer]
PublicKey = <CLIENT publickey>
#this should be the client's set IP with a CIDR of /32
AllowedIPs = <CLIENT_IP>/32
#keepalive setting
PersistentKeepalive = 25
```

The set-up is more-or-less the same as the client one sans some additional details for this to be a bounce server with.

##### Connecting (Server)

Alright, give your server the usual now.
```
wg-quick up wg0
```

It's a similar process to the client. Do note that within the config, your clients should now have an IP address associated with them with some resulting ports (denoted as "Endpoint").

If there's similar routing issues on your server, as described in "Routing (Client)", follow instructions there to clear things up but on your server.


## Adding New Clients

Honestly this is really simple. Follow the client config on a new server that you'd want to connect to the bounce server and get that all set up with `wg-quick up wg0`

Afterwards, within the bounce server's config, just add another peer
![Screenshot from 2023-01-06 13-05-41](https://user-images.githubusercontent.com/93142187/230628232-8211aa98-8e60-4367-b72f-bd547e4d972a.png)


Just like that. Ez.

## Routing traffic through the VLAN

For this, we'll need to use iptables! All of this will be configured on your VPS, the system accepting network traffic from the public internet.

Firstly, check if your system is set to allow portforwarding.
`cat /proc/sys/net/ipv4/ip_forward`
If this is a 1, you're good to go. If not, you can turn it on by running the command `sysctl -w net.ipv4.ip_forward=1`. For systems without `sysctl` you can do it with `echo 1 > /proc/sys/net/ipv4/ip_forward` or just edit it in with `nano /etc/sysctl.conf`.

There's a line that you'll need to add to your firewall in order for it to route traffic through properly:
```
iptables -t nat -A PREROUTING -i <internet interface> -p tcp --dport <port you want to forward> -j DNAT --to-destination <IP for wireguard endpoint>
```

This can also be formatted to accept multiple ports as well, all at once (15 at a time?):
```
iptables -t nat -A PREROUTING -i <internet interface> -p tcp -m multiport --dports <ports>,<separated>,<by>,<commas> -j DNAT --to-destination <IP for wireguard endpoint>:<specific port>
```

Afterwards, be sure to follow these rules with respective forwarding rules for them.
```
iptables -A FORWARD -p tcp -d <IP for wireguard endpoint> --dport <port> -j ACCEPT
```

You may also need to add in a rule for some conntrack parameters. Be sure to add it before all other rules with an `iptables -I FORWARD 1` if necessary.
```
iptables -A FORWARD -i <host nic> -o wg0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -i wg0 -o <host nic> -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
```

Additionally a `POSTROUTING` rule may be necessary for making sure that the connection can be successful.
```
iptables -t nat -A POSTROUTING -o wg0 -p tcp --dport <desired port> -d <VLAN Client address> -j SNAT --to-source <VLAN Host Address>
```

Sources:
  - https://serverfault.com/questions/1067746/port-forwarding-with-wireguard
  - https://www.systutorials.com/port-forwarding-using-iptables/
  - https://lewiswalsh.com/port-forwarding-with-iptables-for-wireguard/

An example of successful config would look like this:
```
iptables -t nat -A PREROUTING -i enp1s0 -p tcp --dport 45874 -j DNAT --to-destination 10.0.10.3

iptables -A FORWARD -p tcp -d 10.0.10.3 --dport 22978 -j ACCEPT

iptables -t nat -A POSTROUTING -o wg0 -p tcp --dport 37948 -d 10.0.10.3 -j SNAT --to-source 10.0.10.1
```

This is telling our VPS:
1. From the incoming interface, enp1s0, any traffic that hits the port will need to be sent over to our WG VLAN address. Essentially reserving the port for that address.
2. All traffic incoming from the port gets forwarded to the aforementioned address.
3. Any resulting traffic that returns, in reply, gets routed out from the VPS


## Troubleshooting or misc issues

- Make sure that you allow a firewall rule for ICMP and for the WG listening port if you haven't, for one. Sometimes things get stuck until the two peers can properly handshake, which a ping will generally do

- If wg-quick isn't working, double-check your config files. Also make sure that the config files are where they need to be (`/etc/wireguard/wg0.conf`). `resolvconf` (on debian-based systems) should be installed too. Note that wg-quick deletes comments as well in the conf file.

- If you mess up with the prerouting rules, you can check on them with `iptables --list PREROUTING -t nat` or `iptables --list POSTROUTING -t nat`  Then delete the rule with `iptables -t nat -D PREROUTING <rule line number>` Also an addemdum to this, you can `grep` a specific rule with a `| grep <port>` at the end

- Make sure that your IP addresses are PRECISELY CORRECT. Double-check all rules if you aren't sure.

- On Windows machines where you're trying to open a firewall rule on, WG may count as a public profile rule instead of a private one. If a port isn't opening on the private profile then try using it on the public one.
  
- If you try to ping your bounce server and nothing's getting through, try setting iptables OUTPUT policy to `ACCEPT` for a moment (or find which port it's trying to ping with in /var/log/messages). Once the ping goes through, it should work regardless of the state of the firewall, though you should be sure to define a `ListenPort` in the client conf after the fact (and set the appropiate firewall rule as well).

## Tips
- `wg syncconf wg0 <(wg-quick strip wg0)` Refreshes config without having to take the interface down (doesn't work in fish shell btw)

- If you want to check the ping of MC servers and have that feature functioning properly, you'll have to make respective rules for everything but in UDP on the VPS' side

- nmap on UDP isn't possible without running a specific command (run as sudo, `nmap -sU <ip or host>`) https://nmap.org/book/scan-methods-udp-scan.html
