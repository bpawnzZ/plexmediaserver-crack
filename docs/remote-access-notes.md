# Remote access — working notes

Deep-dive companion to the README's
[Remote access](../README.md#-remote-access-without-a-plex-pass) section. The
README carries the answer; this file carries the reasoning, the measurements and
the wrong turns — so they do not have to be re-derived, and do not have to be
read by someone who just wants the setup working.

**Status:** remote access over a VPN mesh works. The cause of the failure that
took the longest to find was a missing `PersistentKeepalive` on a NAT'd peer.
Everything below is either (a) that investigation, (b) a real but *different*
failure mode worth knowing, or (c) explicitly refuted and kept only so nobody
chases it again.

A note on reading this: anything marked **measured** was observed on a live
server and is repeatable. Anything marked **hypothesis** was not. Where a
hypothesis was later killed, it is kept with its refutation attached rather than
quietly deleted, because the reasoning is the useful part.

---

## 1. Which mesh, and why it matters

| | ZeroTier / Tailscale | Plain WireGuard |
|---|---|---|
| Reach the server at its mesh IP | ✅ | ✅ |
| Server classifies the client as local | ✅ | ✅ *(measured — see §3)* |
| Remote playback without a Pass | ✅ | ✅ |
| Setup effort | join network, authorise | configure a hub + per-client keys, **and a keepalive on every NAT'd peer** |

The mesh only decides how packets reach the server. It does not decide whether
the server treats you as local — Plex tags mesh clients and tunnel clients both
as `(Subnet)`.

What differs is failure behaviour. ZeroTier and Tailscale do their own NAT
traversal and keepalive; **plain WireGuard does not keep a NAT mapping alive for
you**, and that asymmetry is the entire reason the same Plex setup can be fine
on one mesh and dead on another.

---

## 2. The failure, and how it was found

**Symptom:** Plex would not load at all over WireGuard — not slow, *nothing*,
then "eventually" it might appear. Sometimes a Plex Pass prompt instead.
ZeroTier on the same server worked normally.

**Cause (measured):** the peer behind NAT had no `PersistentKeepalive`. A NAT'd
peer is only reachable at the endpoint its NAT last saw it use, and that mapping
expires after roughly 30–120 s of silence. Once it expires, packets the *other*
peers send toward it are dropped at the hub. The failure is **one-way**:

| Direction | Result |
|---|---|
| NAT'd peer → hub → everyone else | ✅ works — sending is what reopens the mapping |
| everyone else → hub → NAT'd peer | ❌ dropped while the mapping is cold |

**Fix:** on the NAT'd peer,

```ini
[Peer]
AllowedIPs = 10.13.13.0/24
PersistentKeepalive = 25
```

Apply it live without disturbing the handshake, then persist it:

```sh
sudo wg set wg0 peer <hub-public-key> persistent-keepalive 25
```

**Confirmed** by leaving the link deliberately silent for 150 s and re-testing:
the hub then reached the peer with `4/4` ping and `HTTP 200` from Plex over the
tunnel, and Plex's log showed the client's requests landing again.

### Why it was so hard to see

Every casual diagnostic looks healthy:

- `wg show` reports a recent handshake (the client's own keepalive-free traffic
  keeps the *outbound* mapping warm enough to handshake).
- Transfer counters climb — a client can pull hundreds of MB *out* while nothing
  can reach *in*.
- Pings **from** the affected host succeed. Only traffic **toward** it fails.

What gives it away is the application log, not the network: a client whose
source address has **zero** logged requests for hours *while data was flowing
outbound to it* is the tell. Test each direction separately.

### The wrong turns, in the order they were taken

Each of these was a plausible, arithmetic-backed theory. Each was killed by
measurement, and each cost real time. They are listed here so they are not
re-tried.

| Theory | Verdict | What killed it |
|---|---|---|
| Plex classifies WireGuard clients as remote, so they fall back to Relay | ❌ **refuted** | Plex tags them `(Subnet)`. See §3. |
| The DNS layer is what makes remote playback work | ❌ refuted | DNS governs name resolution; it does not gate playback. See §6. |
| A UFW rule was blocking the tunnel interface | ❌ **refuted** | The hub already got `0% loss` and `HTTP 200` *before* any rule was added. |
| An MTU mismatch caused the stall | ❌ non-causal | The arithmetic fits and the mismatch was real, but fixing it changed nothing. See §5. |
| The client's bare `/32` address is the cause | ❌ superseded | The prompt was the Relay fallback for a broken path. See §4. |

One rule that would have saved most of this: **change one thing, then re-test the
actual symptom.** Three separate "fixes" were applied-and-believed before the
keepalive was found, because the symptom was intermittent enough to look fixed
each time.

---

## 3. What the server actually does (measured)

Plex tags every request with the connection class it assigned, in
`Plex Media Server.log`. Counted over a single log from the reference server:

| Client | Tag |
|---|---|
| LAN client | `(Subnet)` ×2598 |
| ZeroTier mesh client | `(Subnet)` ×30 |
| **WireGuard tunnel client** | **`(Subnet)` ×82, `(WAN)` ×0** |

**Plex already classifies WireGuard clients as local** — the same bucket as LAN
and mesh clients, with not a single `(WAN)` among them. The only `(WAN)` entries
in that log came from an internet scanner probing the port, not from Plex
clients.

This is what refuted the "classified remote → Relay" theory, and it is why the
Pass prompt was re-read as a *symptom* rather than a cause: a client that cannot
hold a working connection is a client that falls back to the Relay, and the
Relay is the thing that prompts.

So: the server-side verdict was never the problem.

---

## 4. The client-side `/32` question — superseded

**This section records a dead end. Skip it unless you are re-opening the
question.**

Having established that the server says local while the app said remote, the
remaining candidate was the client: the Plex app decides from its *own* tunnel
interface, and a client whose tunnel address carries a bare `/32` has no local
subnet containing the server. On that theory, widening the client's `Address`
mask to `/24` would make the app conclude "same subnet" and stop prompting.

That theory is **superseded**, not proven wrong: the prompt turned out to be the
Relay fallback for a broken path (§2), so the `/24` was never needed. It is also
harmless — see §5 — so a client already carrying `/24` can stay that way.

The test that would have separated the two cases, kept because the method is
still useful for any future classification question — run it from the server
while a stream from the affected client is playing:

```sh
docker exec plex sh -c 'T=$(grep -oP "PlexOnlineToken=\"\K[^\"]+" \
  "/config/Library/Application Support/Plex Media Server/Preferences.xml"); \
  curl -s "http://127.0.0.1:32400/status/sessions?X-Plex-Token=$T"' \
  | grep -oE 'local="[01]"|address="[^"]+"'
```

- `local="1"` **and the prompt still showing** ⇒ the cause is client-side.
- `local="0"` ⇒ the server gate is the cause after all, and the `(Subnet)` tags
  above do not mean what they look like.

---

## 5. The two tunnel knobs: `Address` and `AllowedIPs`

These get conflated constantly, and they are unrelated.

| Knob | Set it wide? | Why |
|---|---|---|
| **`Address`** (interface address + mask) | **safe** | `10.13.13.3/24` merely gives the client a local subnet containing the server. Nothing on either side breaks. `/32` is the textbook value for a single-host peer; the mask adds nothing functional, because routing is done by `AllowedIPs`. |
| **`AllowedIPs`** (crypto-routing table) | **trap on the server** | see below |

**The `AllowedIPs` trap — measured, not theorised.** Giving *every* peer the same
wide range (the linuxserver image's
`SERVER_ALLOWEDIPS_PEER_*=<tunnel-subnet>`) does **not** build a mesh.
WireGuard's kernel resolves overlapping `AllowedIPs` across peers by dropping the
earlier entries, so once every peer claims the whole subnet, `wg show` collapses
19 of 20 peers back to `/32` and **only the last peer keeps the range** — and
which peer that is can rotate on restart. It happens to still work, because the
per-peer `/32`s win by longest-prefix match, but the wide range is decorative and
the ordering is undefined.

The generated **per-peer `/32` table is correct as-is. Leave it alone.**

### MTU: the arithmetic and why it was a red herring

WireGuard adds ~60 bytes of overhead (IPv4), so a client's tunnel MTU must fit
the **smallest egress link on the path**. In a hub-and-spoke mesh that is the
**hub's** link, because the hub re-encapsulates forwarded traffic:

| Link | MTU | Largest inner packet |
|---|---|---|
| hub `eth0` (egress) | 1400 | 1400 − 60 = **1340** |
| hub `wg0` | 1320 | sized correctly, 20 bytes of slack |
| a client `wg0` on the 1420 default | 1420 | **80 bytes too big** |

A packet from peer A to peer C is encapsulated, crosses the hub, and is
**re-encapsulated** for peer C — and on a 1400-MTU hub that second envelope does
not fit. WireGuard sets DF, so it is dropped rather than fragmented, and recovery
depends on ICMP PTB surviving the whole path.

**Measured from a client that came up at the 1420 default** — a real cliff, not a
theoretical one:

```
payload 1280 (total 1308): OK
payload 1300 (total 1328): FAIL  ->  ping: sendmsg: Message too large
```

So the mismatch is real and worth fixing: `MTU = 1320` in each client's
`[Interface]` (or `1280`, the IPv6-safe floor). The linuxserver image sizes the
*hub's* `wg0` from its `eth0` correctly but writes **no MTU at all** into client
configs.

**But it was not the cause of the failure in §2.** Changing it fixed nothing.
Rank it as config hygiene that prevents a distinct class of large-packet loss —
particularly for UDP, where PMTUD does not save you — not as the answer to "the
tunnel appears not to work".

---

## 6. DNS: a real requirement, and a real failure mode

Keep this separate from the Pass prompt. Both problems present as "the mesh is
broken", which is exactly why they get conflated — but fixing DNS does not fix a
playback problem, and a playback problem is not evidence of a DNS fault.

**Run your own resolver, and make sure it can resolve and reach hosts on
whichever VPN network you chose.** That resolver turns "reachable by IP" into
"reachable by name", and it is the layer that ties a mesh together. Get it right
and either mesh works; get it wrong and you will blame the VPN.

Two properties matter:

- **It answers on your VPN network.** Any host on the mesh can query it and get
  mesh addresses back.
- **DNS traffic stays on the internal path.** Queries go to the resolver over the
  VPN only, so nothing is exposed and there is nothing to leak.

An address on one mesh is reachable **only over that mesh**. If you run several,
the resolver must be reachable from each, and the router between them has to
forward:

```sh
# each mesh is a separate interface, and forwarding between them is allowed
ufw route allow in  on wg0     # wg0 <-> anywhere
ufw route allow out on wg0
```

With `DEFAULT_FORWARD_POLICY="DROP"` those rules are what let a client on one
mesh reach a resolver on the other. Remove them and DNS breaks silently while the
tunnel still looks healthy.

**The failure mode is deceptive**, which is why this wastes evenings: a
mesh-specific address works perfectly from any host that happens to be on that
mesh, so testing from the wrong machine makes a broken config look correct.

Two real failures, one box:

1. **`PEERDNS=<mesh-only-ip>` in a WireGuard hub.** Generated client configs
   carried a resolver address reachable only over ZeroTier. The phone had no
   route to it, so *every* DNS lookup failed and the device looked like it had no
   internet at all — while the tunnel itself was fine. Fixed by removing the
   `DNS` line from the client template, so clients keep their own resolver.
2. **`/etc/docker/daemon.json` pinned `"dns": ["<mesh-only-ip>"]`** for every
   container on the host. When that mesh is down, **name resolution inside every
   container dies with it.** Plex is unaffected (it talks to IPs), but anything
   that resolves a hostname is not.

The fix is ordering, not removal — list resolvers so at least one is always
reachable:

```json
{ "dns": ["<mesh-resolver-ip>", "<public-resolver-ip>"] }
```

Ordering is a real trade, so choose deliberately:

- **Internal resolver first** — everything resolves through the self-hosted
  resolver on the mesh, with filtering intact.
- **A public resolver second** — a safety net, at the cost of occasionally
  resolving outside your own DNS.

Two gotchas when you apply it:

- **`systemctl reload docker` does not apply a `dns` change.** dockerd logs
  `Reloaded configuration` while its *effective* config still lists the old
  servers. You need a full `systemctl restart docker`. Containers with a restart
  policy (`always` / `unless-stopped`) come back on their own.
- **Verify from inside a container**, not from the host — they are different
  network namespaces:

  ```sh
  docker exec plex cat /etc/resolv.conf   # your new server must be listed
  ```

---

## 7. Plex preferences: one that matters, three that do not

**`LanNetworksBandwidth` — "LAN Networks" — is the explicit allow, and the one
preference in this area that changes real behaviour.** Plex's own description:

> … networks that will be considered to be on the local network when enforcing
> bandwidth restrictions. **If left blank, only the server's subnet is considered
> to be on the local network.**

That default is the entire ZeroTier/WireGuard asymmetry, and it is **not** about the
client's mask. The server's subnets are whatever its own interfaces say — so a
ZeroTier client lands inside the wide subnet the server itself is on and counts as
local, while a WireGuard client does not land inside the server's `wg0` address —
that address is a `/32`, a single host — and is therefore classed **external**,
subject to external bandwidth restrictions.

Set both meshes explicitly rather than relying on that accident:

```sh
curl -s -X PUT -H "X-Plex-Token: $TOK" \
  "http://127.0.0.1:32400/:/prefs?LanNetworksBandwidth=<lan-subnet>,10.13.13.0/24,<zerotier-subnet>"
```

Bandwidth classification only — it does not fix reachability and does not suppress
the Pass prompt. Write it through the API, never by hand-editing `Preferences.xml`
(Plex rewrites that file itself).

Chasing the Pass prompt through the remaining preferences does waste time. Measured,
on a signed-in server:

| Setting | Reality |
|---|---|
| `customConnections` | Publishes a URI to plex.tv, but the client still does not prefer it. |
| `allowedNetworks` | **Must stay empty.** It grants access **without login**, and only applies when the server is signed *out*. Filling it with a mesh subnet opens **unauthenticated** access to anything on the mesh. |
| `secureConnections` | `1` means **Preferred** — Plex's enum is inverted (`1:Preferred\|0:Required`). Do not "fix" it to `0`; that is the *stricter* setting and breaks plain-HTTP mesh clients. |

---

## 8. Debug order

Network first, preferences never.

1. **Can the client reach the server at its tunnel IP?**

   ```sh
   curl http://<tunnel-ip>:32400/identity
   ```

   If that answers, the network is up and the problem is *not* reachability —
   which means it is not a routing, firewall or DNS fault either.
2. **Is the link healthy in *both* directions, and is a keepalive set?**

   ```sh
   sudo wg show                                  # handshake age + persistent-keepalive
   ping -c3 <server-tunnel-ip>                   # client -> server
   # and from the server:
   ping -c3 <client-tunnel-ip>                   # server -> client  ← the one that fails
   ```

   `persistent-keepalive: off` on a NAT'd peer is a fault, not a default. A
   one-way failure is the signature of §2.
3. **Does the client resolve names at all?** If not, you are in the DNS problem
   in §6, and it is unrelated to playback.

---

## What is still genuinely open

Nothing about reachability. The two questions left are both about *Plex's own
behaviour*, and neither blocks a working setup:

1. Whether the `Address` `/24`-versus-`/32` choice changes what the Plex **app**
   concludes about a connection. The theory was never tested cleanly, because the
   real fault was found first. To test it properly you need a working path and a
   client that still prompts — a situation that no longer reproduces here.
2. Whether the prompt can still appear on a *working* connection for any other
   reason. Nobody has seen it since the keepalive fix.
