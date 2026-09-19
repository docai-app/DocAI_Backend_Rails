# Redis containment — staged change, not a completed release

User authorized Redis protection, lost-work audit, worker alignment, health alerts,
and two frontend fixes on 2026-09-19. No migrations and no blanket historical rerun.

## Stage 1: preserve evidence, contain ingress without interrupting queues

`ops/reliability/redis_ingress_guard.py` first snapshots private Docker/network,
Redis INFO/client/log and firewall evidence (root-only, outside Git). It then adds
only TCP 6379 drops on the operator-confirmed public interface in IPv4 Docker
forwarding / host INPUT and IPv6 where available. It never flushes Redis or
firewall rules, changes SSH, or restarts a service. Default mode is dry-run.

Confirm actual clients first: currently the four Rails/Sidekiq containers on the
application network. Do not assume other environments have the same topology.
Run using the exact GitHub commit, an explicit interface and a new private
evidence directory. Check internal PING, queue workers and external connectivity.
Existing public connections are intentionally blocked, not allowed by an earlier
ESTABLISHED rule; the rule is inserted before Docker forwarding accepts.

Rollback removes only the exact commented rules with `--remove --apply`. It
reopens exposure and must not be routine recovery. The evidence remains private.

**This first stage is runtime containment, not persistent hardening.** Reboot/
Docker recreation, Redis ACL/password rollout, all client configurations, safe
worker switching and registry/delivery acceptance still require the next stages.
Do not claim this file means they have been completed. No secret is committed.
