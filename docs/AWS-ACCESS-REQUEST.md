# AWS access request — ECR mirror for the base images

A provisioning request for the AWS/IT team. Everything below is optional to the
project's function: the images publish to GHCR today. This buys pull
reliability and speed for CodeBuild, and removes a third-party registry from
the critical path of every production build.

## What this is for

`SilverAssist/docker-base` builds two base container images used by 24
production Dockerfiles (12 WordPress, 12 Next.js). GitHub Actions builds them
and needs to push to Amazon ECR; CodeBuild needs to pull from it.

We are asking for **push access from GitHub Actions to exactly two ECR
repositories**, and **pull access for the existing CodeBuild roles to those
same two repositories**. No other AWS service, resource, or account is
involved.

## Why not just pull from a public registry

CodeBuild egresses through shared NAT addresses. Public registries rate-limit
per source IP — Docker Hub allows 10 pulls/hour unauthenticated — and a
throttled or failed pull fails the build. We have already lost production
builds to exactly this class of failure against `api.github.com`. An in-region
ECR mirror has no rate limit, needs no internet egress, and costs no data
transfer.

## Request 1 — Two ECR repositories

| Setting | Value |
|---|---|
| Names | `wp-base`, `next-base` |
| Region | same region as the CodeBuild projects |
| Tag mutability | `MUTABLE` (the `1`, `1.0` and `latest` tags must move) |
| Scan on push | enabled |
| Encryption | AES256 (default) is sufficient |

A lifecycle policy is optional but recommended, to keep storage bounded:

```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep the 30 most recent images",
      "selection": {
        "tagStatus": "any",
        "countType": "imageCountMoreThan",
        "countNumber": 30
      },
      "action": { "type": "expire" }
    }
  ]
}
```

## Request 2 — GitHub OIDC identity provider

Required only if the account does not already have one. It lets GitHub Actions
assume a role using a short-lived OIDC token, so **no long-lived AWS access
keys are created or stored in GitHub**.

| Setting | Value |
|---|---|
| Provider URL | `https://token.actions.githubusercontent.com` |
| Audience | `sts.amazonaws.com` |

AWS manages this provider's certificate thumbprint automatically; no rotation
task is created by this request.

## Request 3 — IAM role for GitHub Actions

Suggested name: `github-actions-docker-base-ecr-push`.

### Trust policy

The `sub` condition is the security boundary: only workflows in this one
repository, and only on release tags, can assume the role. A pull request from
a fork cannot, and neither can any other SilverAssist repository.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": [
            "repo:SilverAssist/docker-base:ref:refs/tags/wp-base/*",
            "repo:SilverAssist/docker-base:ref:refs/tags/next-base/*",
            "repo:SilverAssist/docker-base:ref:refs/heads/main"
          ]
        }
      }
    }
  ]
}
```

> The `refs/heads/main` entry covers `workflow_dispatch` rebuilds, which is how
> a CVE is picked up without cutting a new version. Drop it if IT prefers that
> releases only ever come from tags.

### Permission policy

Scoped to the two repositories. `GetAuthorizationToken` cannot be resource
scoped — that is an AWS constraint, and it only returns a token whose usefulness
is bounded by the second statement.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AuthenticateToECR",
      "Effect": "Allow",
      "Action": "ecr:GetAuthorizationToken",
      "Resource": "*"
    },
    {
      "Sid": "PushBaseImages",
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
        "ecr:DescribeRepositories",
        "ecr:DescribeImages"
      ],
      "Resource": [
        "arn:aws:ecr:<REGION>:<ACCOUNT_ID>:repository/wp-base",
        "arn:aws:ecr:<REGION>:<ACCOUNT_ID>:repository/next-base"
      ]
    }
  ]
}
```

`BatchGetImage` and `GetDownloadUrlForLayer` are read actions, needed because a
multi-architecture push reads back the manifests it just wrote.

## Request 4 — Pull access for CodeBuild

The **existing** CodeBuild service roles need read access to the two new
repositories. This is an addition to roles that already exist, not a new role.

Either attach this policy to each CodeBuild service role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ecr:GetAuthorizationToken",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchCheckLayerAvailability"
      ],
      "Resource": [
        "arn:aws:ecr:<REGION>:<ACCOUNT_ID>:repository/wp-base",
        "arn:aws:ecr:<REGION>:<ACCOUNT_ID>:repository/next-base"
      ]
    }
  ]
}
```

...or, if IT prefers to manage access on the repository rather than on each
consumer, attach an ECR repository policy to `wp-base` and `next-base`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCodeBuildPull",
      "Effect": "Allow",
      "Principal": {
        "AWS": ["arn:aws:iam::<ACCOUNT_ID>:role/<CODEBUILD_SERVICE_ROLE>"]
      },
      "Action": [
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchCheckLayerAvailability"
      ]
    }
  ]
}
```

The repository-policy form still requires each CodeBuild role to hold
`ecr:GetAuthorizationToken`, which most already do — they pull and push their
own application images from ECR today.

## What we are not asking for

Stated explicitly so the review is quick:

- No access to any ECR repository other than `wp-base` and `next-base`
- No long-lived IAM users or access keys
- No permission to delete images or repositories
- No access to S3, Secrets Manager, ECS, RDS, or any other service
- No cross-account access
- No changes to existing CodeBuild roles beyond adding pull on two repositories

## What we need back

| Item | Used as |
|---|---|
| The role ARN from Request 3 | GitHub Actions variable `AWS_ECR_ROLE_ARN` |
| The region | GitHub Actions variable `AWS_REGION` |
| Confirmation Request 4 is applied | so CodeBuild can pull |

Both are repository **variables**, not secrets — a role ARN is not sensitive,
and the trust policy is what actually restricts who can assume it.

## Cost

Storage is billed at roughly $0.10/GB-month. The two images total well under
1 GB, and the lifecycle policy caps growth. In-region pulls from ECR to
CodeBuild incur no data transfer charge — this request slightly *reduces*
egress versus pulling from a public registry.

## Verification

Once provisioned, this confirms the whole chain without deploying anything:

```bash
# 1. The role is assumable and can authenticate
gh workflow run "Build wp-base" -f version=1.0.0 --repo SilverAssist/docker-base

# 2. The image landed in ECR
aws ecr describe-images --repository-name wp-base --region <REGION>

# 3. A CodeBuild role can pull it
aws ecr get-login-password --region <REGION> \
  | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com
docker pull <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/wp-base:1.0.0
```
