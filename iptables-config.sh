#!/bin/bash

# This is assuming you are starting from a completely fresh
# install of iptables with no prior experience of knowledge.
# As far as I'm concerned, it's a simple copy-and-paste to 
# get it all up and running.

# I would not recommend running this as a script just yet,
# as one of the policies are to drop all incoming connections.
# If you were SSH'ing into a server, this would terminate the
# connection.
# I'll fix it to where it asks for a default, friendly 
# connection so it can be executed as a script eventually.
# Copy-psting will do for now.

# Addendum: this is easier to copy-paste following a 
# sudo -s command

# ====================
# = Beginning set-up =
# ====================

# Define four tables to add to INPUT and OUTPUT chains
# FRIENDLY: Known, desired connections
# MALICIOUS: Known, unfriendly ports or rules to sift
# out trash packets
# INPORTS: Essentially "INPUT" table but helps to organize
# the rules that get opened or closed for specific ports.
# Purely for organizational purposes.
# OUTPORTS: Similar to INPORTS. You could honestly name these
# whatever, as long as it works for you.

iptables -N FRIENDLY
iptables -N MALICIOUS
iptables -N INPORTS
iptables -N OUTPORTS

# Set order of tables. Order is as follows for incoming connections:
# INPUT -> MALICIOUS -> INPORTS -> FRIENDLY -> DROP
# Order runs incoming connections through malicious table to check
# if it's bogus traffic or malicious traffic.
# Connection runs through INPORTS to check if there's any open ports
# to access.
# Finally, rule runs through FRIENDLY table to see if the source is from
# a known, desired source (these get accepted immediately).
# If a connection fails all-else, drop it.

iptables -I INPUT 1 -j MALICIOUS
iptables -I INPUT 2 -j INPORTS
iptables -I INPUT 3 -j FRIENDLY
iptables -I OUTPUT 1 -j OUTPORTS

# If a connection is defined as already established, desired traffic
# or related to such traffic, allow it. Otherwise you wouldn't be
# able to do much at all outside of the firewall, would you?
# These sit on top of the INPUT and OUTPUT tables

iptables -I INPUT 1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -I OUTPUT 1 -m conntrack --ctstate ESTABLISHED -j ACCEPT

# Logging rules. These track what hits the very end of the list of rules
# before being dropped. So the table looks like this now:
# INPUT -> MALICIOUS -> INPORTS -> FRIENDLY -> LOG -> DROP
# These should remain at the end of your INPUT and OUTPUT tables. Log files
# are generally outputted into /var/log/kern.log or /var/log/messages

iptables -A INPUT -p tcp -m tcp -j LOG --log-prefix "tcp.in.dropped "
iptables -A INPUT -p udp -m udp -j LOG --log-prefix "udp.in.dropped "
iptables -A OUTPUT -p udp -m udp -j LOG --log-prefix "udp.out.dropped "
iptables -A OUTPUT -p tcp -m tcp -j LOG --log-prefix "tcp.out.dropped "

# ==========================
# = Input and Output rules =
# ==========================

# INPORTS table. We will begin with some simple rules to allow for connectivity
# ----------------------------------------------------------------------------------

iptables -A INPORTS -i lo -m comment --comment "allow loopback" -j ACCEPT
iptables -A INPORTS -p tcp -m comment --comment "SSH standard port, only for known friendly connections" -m tcp --dport 22 -j FRIENDLY
iptables -A INPORTS -p icmp -m comment --comment "allow icmp from friendly connections" -j FRIENDLY

# The first rule allows loopback connections to work. We need this
# The second rule will allow us a SSH connection from a known, friendly
# connection defined in the "CONNECTION" table
# Third rule allows ICMP ping from friendly sources only. This is a bit moot
# to have and sort of gets in the way of monitoring server uptime but might
# ease some anxieties about being pinged to high-hell and back by bots on the
# web. Set it to "-j ACCEPT" instead.

# This is how you add new incoming rules to your table

# iptables -A INPORTS -p tcp -m tcp --dport <DESIRED PORT> -m comment --comment "insert comment here" -j ACCEPT

# -A: Append rule to given table (INPORTS)
# -p: Procol. tcp or udp.
# -m: Match to a module. For this, we use it for defining TCP/UDP behavior or
# to define a comment. I like to use comments to organize my tables. I recommend
# you to do the same.
# That being said, the match is being used to match the protocol to a desired port.
# --dport: Destination port. The port of which traffic is coming into.
# -j: "Jump" or just what the rule should do when a connection matches this rule.
# Typically, with incoming port traffic, you'll want to "ACCEPT" the traffic, but you
# could also throw it at another table, like the "FRIENDLY" table.

# OUTPORTS Table now.
# ----------------------------------

iptables -A OUTPORTS -o lo -m comment --comment "allow loopback" -j ACCEPT
iptables -A OUTPORTS -p tcp -m tcp --sport 80 -m comment --comment "allow outbound http" -j ACCEPT
iptables -A OUTPORTS -p tcp -m tcp --sport 443 -m comment --comment "allow outbound https" -j ACCEPT

# Loopback is self-explanitory
# Outbound port 80 and 443 will allow your system to run curl commands and to be able to
# update itself with an apt-get update, dnf update or otherwise.
# DNS can be a little tricky here, however, as that's a part of allowing updates to go
# through. You need to be able to resolve nameservers after all.

# In my experience, it varies between systems. On my VPS, I have this rule that allows package
# managers to resolve their addresses.

iptables -A OUTPORTS -p udp -m udp --sport 53 -m comment --comment "allow DNS resolution" -j ACCEPT

# However, on something like my machine that I use to proxy my internal connections from traffic within
# my LAN, the rule is different.

iptables -A OUTPORTS -p udp -m udp --dport 53 -m comment --comment "allow DNS resolution" -j ACCEPT

# Don't ask me why that needs a dport rather than a sport. It just works.

# And, as always, if you want to append a rule to your OUTPORTS table:

# iptables -A INPORTS -p tcp -m tcp --sport <DESIRED PORT> -m comment --comment "insert comment here" -j ACCEPT

# --sport: Source port. Since the traffic is originating from there and not elsewhere. 


# ========================
# = The Other Tables Now =
# ========================

# Here's the MALICIOUS TABLE now. I'll explain what each of these rules are doing.
# ---------------------------------------------------------------------------------------

iptables -A MALICIOUS -m conntrack --ctstate INVALID -m comment --comment "Drop trash packets #1" -j DROP
iptables -A MALICIOUS -p tcp -m tcp --tcp-flags FIN,SYN FIN,SYN -m comment --comment "Drop trash packets #2" -j DROP
iptables -A MALICIOUS -p tcp -m tcp --tcp-flags SYN,RST SYN,RST -m comment --comment "Drop Trash packets #3" -j DROP
iptables -A MALICIOUS -p tcp --tcp-flags ALL NONE -m comment --comment "block null packets" -j DROP
iptables -A MALICIOUS -f -m comment --comment "block fragmented packets" -j DROP
iptables -A MALICIOUS -p tcp ! --syn -m state --state NEW -m comment --comment "force SYN checks" -j DROP
iptables -A MALICIOUS -p tcp --tcp-flags ALL ALL -m comment --comment "block XMAS packets" -j DROP

# 1. If the packet is just some invalid garbage, drop it
# 2. Flags don't make sense.
# 3. Flags also don't make sense.
# 4. Block NULL packets, which are commonly used for recon. NULL packets are just TCP packets with no flags set to them.
# 5. Block fragmented packets. Specific attack vector for attempting to send Linux servers into kernel panics. Generally
# can be caught with other rules and isn't THAT MUCH of a worry for smaller, self-hosted instances, but it's a good just-in-case
# 6. Force SYN (Syncronize) checks. SYN-Packet-Flooding is a type of potential DoS attack where SYN packets are sent to a server
# but don't request anything (an ACK, acknowledgement). This rule only allows for SYN packets that actually request something
# so that our resources aren't eaten up by malicious packets
# 7. Stops XMAS (Christmas) packets. XMAS packets are packets with their flags all set to "1". This is generally used as a type
# of recon packet, where, depending on the response to those flags, an actor could gauge what type of system or firewall you're
# running. Not inherently disruptive to self-hosting operations but also are generally unwelcome.

# As always, if you want to add something like a known, malicious IP to this table, simply add it with this rule here:

# iptables -A MALICIOUS --source <source, malicious IP> -j DROP

# --source: You can add specific rules by a source IP or range, even. For a range of IP's, you could use CIDR notation (0.0.0.0/24) or
# a range of IP addresses (-m iprange --src-range 0.0.0.0-0.0.0.0)
# This can be done to specific ports too in particular, though I'd imagine any address of which is malicious, you wouldn't want it
# pinging TOO much of anything else there

# Here comes the FRIENDLY table, the last, good one
# -----------------------------------------------------

# This table is the most straightforward. You're really only allowing a specific IP, subnet, range or those previous, three things
# paired with a port or port range. Here's an example of an extensive FRIENDLY rule.

# iptables -A FRIENDLY -p tcp -m tcp -m iprange --src-range 0.0.0.0-0.0.0.0 -m comment --comment "friendly range" -j ACCEPT

# A rule of thumb I like to follow with the friendly table: The more specific you can be with it, the better. You'd want to
# add in your home IP as a known, friendly connection, which is fine, but for more specific applications (such as porting traffic
# through a VLAN or VPN), you'd want to define specific ports or port ranges along with specific IP's. IP spoofing is a thing, after
# all.

# Also add these too after your rules here (make sure these remain at the end of your FRIENDLY table, FRIENDLY rules will typically
# require the -I flag.)

iptables -A FRIENDLY -p tcp -m tcp -j LOG --log-prefix "tcp.in.foreign"
iptables -A FRIENDLY -p udp -m udp -j LOG --log-prefix "udp.in.foreign"
iptables -A FRIENDLY -j DROP

# This logs connections that get past the INPORTS table and fail, which keeps a log of foreign, unknown connections that try to prod
# their way into your network.

# ==============
# = Conclusion =
# ==============

# That about wraps it up. After you've added your IP as the sole, friendly connection that can hit your SSH port, go ahead
# and set your table's default policies to DROP all connections.

iptables --policy INPUT DROP
iptables --policy OUTPUT DROP
iptables --policy FORWARD DROP

# This makes any invalid or non-predefined connections, rules or attempts to connect invalid and appear to evoke no response from the
# server whatsoever.

# Make sure to save your config with iptables-save by pointing it to a specific file you can reload later
# I recommend installing iptables-persistent, however, as iptables rules don't persist after a reboot.
# iptables-persistent saves rules in rules.v4 at /etc/iptables/rules.v4.

iptables-save > /etc/iptables/rules.v4 

# If you want to manually load rules after messing around, however, it's no biggie:

iptables-restore < /etc/iptables/rules.v4 

# Be sure to save your progress after fiddling with rules and adding/removing rules as well.



# =============
# = CHANGELOG =
# =============

# v.1.0 - Initial commit (03/27/23)
