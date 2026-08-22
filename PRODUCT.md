# Product

## Register

product

## Users

Ada developers and storage operators running Flyology Object Storage locally or
on a controlled host. They need to confirm that the S3 endpoint, selected
backend, and supervised services are healthy before using the server, then
inspect and operate storage without reaching for an unrelated administration
stack.

## Product Purpose

Provide a trustworthy browser workbench for trying, observing, and eventually
administering the Flyology Object Storage server. Success means the operator can
authenticate from the one-time bootstrap credential, understand the exact
runtime and backend in seconds, perform supported management work safely, and
see failures in terms that correspond to the server's supervision model.

## Brand Personality

Precise, capable, and quietly distinctive. The interface should feel like a
serious local instrument with the clarity of a good systems console, not an
enterprise control-panel skin or a toy demo.

## Anti-references

Avoid generic SaaS dashboards, decorative metric-card grids, cloud-console
sprawl, neon terminal cosplay, glass effects, and controls that imply unsupported
capabilities. Do not clone psqlbench's topology-specific complexity; retain its
clear workbench hierarchy, compact technical labels, honest system state, and
supervision visibility.

## Design Principles

1. Show the actual system, including the bound endpoint, backend, authentication
   state, and supervised service health.
2. Make the safe next action obvious, especially during bootstrap, login,
   empty storage, degraded service, and destructive workflows.
3. Use familiar controls and dense information where operators benefit from
   them; spend visual character on hierarchy and craft, not novel affordances.
4. Fail closed and explain recovery without exposing credentials or sensitive
   request details.
5. Keep the browser workbench useful on a laptop and fully operable without a
   mouse.

## Accessibility & Inclusion

Target WCAG 2.2 AA. Preserve visible keyboard focus, semantic landmarks and
status announcements, non-color state cues, comfortable target sizes, reduced
motion, high-contrast system modes, and a responsive single-column workflow for
narrow screens.
