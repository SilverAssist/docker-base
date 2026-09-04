# Versioning

Semver per image, tagged independently: `wp-base/v1.2.0`, `next-base/v1.2.0`.

| Change | Bump |
|---|---|
| Alpine/nginx/Node security rebuild, no interface change | patch |
| New PHP extension, new helper script, non-breaking default | minor |
| Removed extension, changed config path, new major PHP/Node | major |

Each release publishes four tags per registry:

| Tag | Moves | Use |
|---|---|---|
| `1.2.0` | never | pin production here |
| `1.2` | on patch | tolerate security rebuilds |
| `1` | on minor | development only |
| `latest` | every release | never in a Dockerfile |

## Pin by digest in production

```dockerfile
FROM <acct>.dkr.ecr.us-east-1.amazonaws.com/wp-base:1.2.0@sha256:abc...
```

The tag documents intent; the digest is what actually guarantees the bytes.
A tag can be overwritten, a digest cannot. This is the property that was
missing when Composer 2.10.3 entered production builds on its own — see the
root cause in the [README](../README.md#why).

The release workflow prints the digest in its run summary, ready to paste.

## Security rebuilds

A CVE in Alpine or nginx needs no source change: re-run the release workflow
with the same version and it rebuilds against current packages. That publishes
a new digest under the same tags.

Consumers pinned to a digest are unaffected until someone updates them —
which is the point. The upgrade becomes a reviewable commit in each project
rather than something that happens silently on the next build.

`validate.yml` runs Trivy weekly against `main` so an unattended base image
still surfaces new CVEs.
