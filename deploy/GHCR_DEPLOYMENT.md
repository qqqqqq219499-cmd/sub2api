# GHCR Safe Deployment Flow

Goal: GitHub Actions builds the Docker image, while the production server only
pulls a pinned image, switches the `sub2api` service, verifies health, and rolls
back automatically on failure.

## 1. Build Image

Run this GitHub Actions workflow manually:

```text
Build Custom GHCR Image
```

Recommended inputs:

```text
version: 0.1.132
image_repository: leave empty to use the current repository
image_tag: v0.1.132-codex-<short_sha>
run_tests: true
push_latest_custom: false
```

Example output image:

```text
ghcr.io/<owner>/<repo>:v0.1.132-codex-1d890031
```

## 2. Deploy On Server

Copy or keep `deploy-ghcr-image.sh` on the server, then run:

```bash
cd /opt/sub2api
bash /path/to/deploy-ghcr-image.sh \
  --image ghcr.io/<owner>/<repo>:v0.1.132-codex-1d890031 \
  --expected-version 0.1.132 \
  --expected-commit 1d890031
```

The script will:

- `docker pull` the target image
- back up `/opt/sub2api/docker-compose.yml`
- replace only the `sub2api` service image
- run `docker compose up -d --no-deps --force-recreate sub2api`
- wait for container health to become `healthy`
- request `http://127.0.0.1:8080/health`
- verify `/app/sub2api --version`
- restore the compose backup and recreate the old service if a critical check fails

If the current user cannot access Docker or write `/opt/sub2api/docker-compose.yml`,
the script uses passwordless `sudo` automatically. Otherwise run it as root.

## 3. Manual Rollback

If manual rollback is needed:

```bash
cd /opt/sub2api
sudo cp docker-compose.yml.bak.YYYYMMDDHHMMSS docker-compose.yml
sudo docker compose up -d --no-deps --force-recreate sub2api
sudo docker compose ps sub2api
```

Do not run `docker compose down -v`; that removes data volumes.

## 4. Local Verification

Before committing deployment changes:

```bash
cd backend
go test -count=1 ./...
```

Check deployment script syntax:

```bash
bash -n deploy/deploy-ghcr-image.sh
```
