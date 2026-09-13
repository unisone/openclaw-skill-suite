---
name: secure-agent-design
description: Security architecture patterns for personal AI agents that touch real accounts. Use when designing an agent with access to inbox, calendar, finances, or shopping. Covers per-user isolated VMs, pre-action sentinel checks, least-privilege connectors, human approval gates, and single-use payment credentials.
license: MIT
metadata:
  author: unisone
---

# secure-agent-design

Distilled from the security architecture Meta disclosed for Muse (Sept 2026):
each agent runs in its own secure VM, a separate "sentinel" system checks
every action before it leaves the VM, and the agent never sees real passwords
or card numbers. Security framed as architecture, not promises, was the
adoption unlock.

## The patterns

### Per-user isolated compute

Each user's agent runs in its own virtual machine: an isolated computer
dedicated to that user. Compromise of one agent cannot reach another user's
data. The VM keeps working in the background even when the user is away.

### Sentinel: pre-action verification

A separate system checks every action before anything leaves the VM. The
agent proposes; the sentinel verifies against policy (allowed apps, spending
limits, sensitivity rules) before execution. No action with side effects
bypasses this gate.

### Credential isolation

The agent never sees actual passwords or card numbers. Purchases go through
single-use virtual card numbers issued per transaction, so the real payment
credentials never enter the agent's context and can't leak through prompts,
logs, or model outputs.

### Human approval gates

The agent asks before sensitive actions: sending an email, spending money,
deleting data. Approvals should be specific (this action, this amount, this
recipient), not blanket. Routine low-risk actions can run autonomously once
the user opts in.

### Least-privilege connectors

The user decides exactly what the agent can touch: which apps are connected,
whether access is read or read-write, and can revoke anytime. Default to the
narrowest scope that completes the job; expand only on explicit request.

### Transparency

The user can see everything the agent has done: a complete, human-readable
action log. Include "forget" controls so users can delete what the agent
has learned about them.

## Messaging it

Lead with the architecture ("runs in its own secure VM, every action checked
before it leaves"), not with adjectives ("bank-grade," "military-grade").
Name the components (VM, sentinel, single-use cards) so technical users can
verify the claims. Acknowledge the tradeoff honestly: broader access means
higher stakes, which is exactly why the architecture exists.
