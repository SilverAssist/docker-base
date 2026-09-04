# next-base

Two targets, published as two tags.

| Target | Tag | Contents |
|---|---|---|
| `builder` | `next-base:1-builder` | Node 24.20.0, libc6-compat, git, bash, openssh, python3, make, g++ |
| `runtime` | `next-base:1` | Node 24.20.0, nginx, supervisor, bash, findutils, libc6-compat, vips |

## Pinned contents

| Component | Version | Pinning |
|---|---|---|
| Node | 24.20.0 | base image digest |
| Alpine | 3.24 | via the node image |
| nginx | Alpine 3.24 repository | follows Alpine |

nginx here comes from Alpine rather than the official nginx image, because the
runtime needs an exact Node version and only one of the two can come from the
base image. Node is the one that has to match the builder. Alpine 3.24 ships
nginx 1.30.4, which is past the 1.30.1 fix for CVE-2026-42945.

## Why the runtime starts from Node

The project Dockerfiles today start the final stage from `nginx:alpine` and
copy `/usr/lib`, `/usr/local/lib`, `/usr/local/include` and `/usr/local/bin`
out of the Node builder. That moves an unversioned set of shared objects
between two bases that update independently, and breaks quietly when either
one shifts. Starting from Node and adding nginx removes the copy entirely.

## Not included

`entrypoint.sh`, `cache-handler.js`, the nginx server block, and the cache
rotation scripts. These differ per site and stay in the project.

## Extra packages per site

Some sites need more in their own layer: `vips-dev` (cc, osa), `expat`,
`python3`, `py3-pip` (homecare, seniorhomes).
