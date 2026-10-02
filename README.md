# OpenSSH client

Container images with the [OpenSSH](https://www.openssh.com/) client: `ssh`, `scp`, `sftp`, `ssh-keygen`, `ssh-agent`, `ssh-add` and `ssh-keyscan`. OpenSSH is compiled from the signed release tarball on Ubuntu and Alpine, for `linux/amd64` and `linux/arm64`, and the images are rebuilt when OpenSSH publishes a release and when the base image changes. The tools run under any UID, including one that has no entry in `/etc/passwd`.

This is an unofficial build, not affiliated with or endorsed by the OpenSSH project. Report problems with the image in this repository and OpenSSH bugs [upstream](https://www.openssh.com/report.html).

## Quick start

Run a command on a server, with the key and `known_hosts` file from your `~/.ssh`:

```sh
docker run --rm --user "$(id -u):$(id -g)" -v "$HOME/.ssh:/ssh:ro" \
  ghcr.io/randomcontainers/openssh-client \
  -i /ssh/id_ed25519 -o UserKnownHostsFile=/ssh/known_hosts deploy@example.com uptime
```

The entrypoint is `ssh`. Start the other tools with `--entrypoint`, here to copy a file from the current directory:

```sh
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/work" -v "$HOME/.ssh:/ssh:ro" \
  --entrypoint scp ghcr.io/randomcontainers/openssh-client \
  -i /ssh/id_ed25519 -o UserKnownHostsFile=/ssh/known_hosts report.pdf deploy@example.com:/srv/reports/
```

and to create a key pair in it:

```sh
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/work" --entrypoint ssh-keygen \
  ghcr.io/randomcontainers/openssh-client -t ed25519 -N "" -C deploy -f deploy_key
```

Add `-it` for an interactive login, and whenever ssh has to ask for a password or a passphrase. The [OpenSSH manual pages](https://www.openssh.com/manual.html) describe every option.

## Keys, known hosts and configuration

Where `~/.ssh` is inside the container depends on the UID (see [Running as any UID](#running-as-any-uid)), so mount your files at a fixed path such as `/ssh` and name them on the command line: `-i /ssh/id_ed25519 -o UserKnownHostsFile=/ssh/known_hosts`, or `-F /ssh/config` with absolute paths in the config file. ssh ignores a private key that other users can read, so keep the key mode `600`; with `--user "$(id -u):$(id -g)"`, ssh runs as the key's owner and can read it.

Without a terminal, ssh cannot ask whether to trust a host key it has not seen, so the server must already be in the `known_hosts` file. `ssh-keyscan` prints a server's host keys; check their fingerprints (`ssh-keygen -l -f known_hosts`) against the ones the server's administrator gives you before you rely on them:

```sh
docker run --rm --entrypoint ssh-keyscan ghcr.io/randomcontainers/openssh-client example.com >> known_hosts
```

The image has no `/etc/ssh/ssh_config`, so ssh starts from its built-in defaults. Mount a file there, for example `-v "$PWD/ssh_config:/etc/ssh/ssh_config:ro"`, to set options for every host.

OpenSSH uses the post-quantum key exchange `mlkem768x25519-sha256` by default and prints a warning when a server offers no post-quantum key exchange. `-o WarnWeakCrypto=no-pq-kex` turns that warning off. DSA keys no longer work: OpenSSH removed them in 10.0.

## Using an ssh-agent

Mount your agent's socket and point `SSH_AUTH_SOCK` at it, and ssh uses the keys loaded in the agent on the host:

```sh
docker run --rm -it --user "$(id -u):$(id -g)" \
  -v "$SSH_AUTH_SOCK:/agent.sock" -e SSH_AUTH_SOCK=/agent.sock \
  -v "$HOME/.ssh/known_hosts:/ssh/known_hosts:ro" \
  ghcr.io/randomcontainers/openssh-client -o UserKnownHostsFile=/ssh/known_hosts deploy@example.com
```

On Docker Desktop, the host's agent is at `/run/host-services/ssh-auth.sock`: mount that path instead of `$SSH_AUTH_SOCK`.

To run `ssh-agent` inside the container, give it a socket path with `-a`, as in `ssh-agent -a /tmp/agent.sock`. Since OpenSSH 10.1, ssh-agent otherwise puts its socket in `~/.ssh/agent`, which does not exist for most UIDs in the image.

## Running as any UID

OpenSSH refuses to start for a UID that has no entry in `/etc/passwd` (`No user exists for uid 1001`), and `--user "$(id -u):$(id -g)"` usually gives the container such a UID. In this image, `ssh`, `scp`, `sftp`, `ssh-keygen`, `ssh-agent`, `ssh-add` and `ssh-keyscan` in `/usr/local/bin` are links to a short shell script, [`wrapper.sh`](wrapper.sh). When the UID has no entry, the script writes a copy of `/etc/passwd` with an entry for it to a temporary file, then starts the real program from `/usr/local/libexec/openssh/bin` with [nss_wrapper](https://cwrap.org/nss_wrapper.html) preloaded, which makes that file the passwd database. Programs that the tool starts, such as the `ssh` that `scp` runs, inherit the setting. For a UID that has an entry, such as the image's default UID 1000 or root, the script starts the program directly.

The added entry has the user name `ssh` and the home directory `/home/ssh`, which does not exist. For these UIDs:

- ssh logs in to the server as `ssh` when the destination names no user. Always give the remote user: `deploy@example.com` or `-l deploy`.
- `~/.ssh` is `/home/ssh/.ssh`. For UID 1000 it is `/home/ubuntu/.ssh` on Ubuntu and `/home/app/.ssh` on Alpine, and for root `/root/.ssh`. Pass key and `known_hosts` paths explicitly, as above.

Each run that needs the entry leaves a small file in `$TMPDIR`, or `/tmp` when it is not set. With `--read-only`, add `--tmpfs /tmp`.

## What is in the image

- `ssh`, `scp`, `sftp`, `ssh-keygen`, `ssh-agent`, `ssh-add` and `ssh-keyscan`, linked against the distro's OpenSSL (libcrypto), zlib and libedit, which gives `sftp` command-line editing.
- `sftp-server`, and the PKCS#11 and security key helpers that the tools start, in `/usr/local/libexec/openssh`.
- nss_wrapper from the distro, for the wrapper described above.

Not included: `sshd` and `ssh-keysign`; GSSAPI and Kerberos authentication, which Ubuntu's own OpenSSH package has; built-in FIDO/U2F security key support (libfido2); `xauth`, which X11 forwarding needs; `ssh-copy-id`; and the man pages. `ssh -V` prints the OpenSSH and OpenSSL versions, and the configure flags are in `/usr/local/share/randomcontainers/openssh-client/buildinfo`.

## Default or slim

OpenSSH's default image adds no other tools, so `latest` and `slim` are the same image, with the contents listed above. Use `latest` to run it and the `slim` tags as a base for your own image.

## Tags

`<version>` is an OpenSSH portable release such as `10.5p1`. `<major>` is its major version, `10`, and follows the newest release in that series. Each row lists the default tag and its `slim` twin, which point to the same image.

| Tags | Base |
|---|---|
| `latest`, `slim` | Ubuntu |
| `<version>`, `<version>-slim` | Ubuntu |
| `<major>`, `<major>-slim` | Ubuntu |
| `ubuntu`, `slim-ubuntu` | Ubuntu |
| `<version>-ubuntu`, `<version>-slim-ubuntu` | Ubuntu |
| `<major>-ubuntu`, `<major>-slim-ubuntu` | Ubuntu |
| `<version>-ubuntu26.04`, `<version>-slim-ubuntu26.04` | Ubuntu 26.04 |
| `alpine`, `slim-alpine` | Alpine |
| `<version>-alpine`, `<version>-slim-alpine` | Alpine |
| `<major>-alpine`, `<major>-slim-alpine` | Alpine |
| `<version>-alpine3.24`, `<version>-slim-alpine3.24` | Alpine 3.24 |

The images are currently built on Ubuntu 26.04 and Alpine 3.24. Tags without a distro version move to the next distro release when the project does; tags ending in `ubuntu26.04` or `alpine3.24` stay on that release and are no longer rebuilt once the project moves to the next one. Every tag of the current OpenSSH version, including the exact version, is rebuilt in place (see [Updates](#updates)), so pin a digest when you need the same bytes every time.

## Platforms

`linux/amd64` and `linux/arm64`, for both Ubuntu and Alpine. Both are compiled natively on GitHub-hosted runners, without emulation.

## Files and permissions

The working directory is `/work`. The image runs as UID 1000, and any other UID works too: `HOME` is then `/`, and caches go to `/cache`, which anyone can write to. How to get output files owned by you depends on how you run containers:

| Runtime | Flag |
|---|---|
| Docker on Linux (rootful), GitHub Actions | `--user "$(id -u):$(id -g)"` |
| Rootless Podman | `--userns=keep-id` |
| Rootless Docker | `--user 0:0` (root in the container is your user on the host) |
| Docker Desktop on macOS or Windows | none, file ownership is mapped for you |

The same flag lets ssh read keys and config files that only you can read.

## Extending the slim image

Use a `slim` tag as the base for your own image. `slim`, `slim-ubuntu` and `slim-alpine` move to each new OpenSSH release and are rebuilt when the base image changes. ssh reads `/etc/ssh/ssh_config` and `/etc/ssh/ssh_known_hosts` for every user, so an image for a CI job can carry its settings and the host keys it trusts:

```dockerfile
FROM ghcr.io/randomcontainers/openssh-client:slim-ubuntu@sha256:...
COPY ssh_config /etc/ssh/ssh_config
COPY known_hosts /etc/ssh/ssh_known_hosts
```

Use `slim-alpine` for the Alpine image. To install packages, switch to `USER root` and back to `USER 1000:1000` afterwards. The entrypoint is `["tini", "--", "ssh"]`; set your own `ENTRYPOINT` if your image runs something else. To pick up new OpenSSH releases and base image fixes, let Dependabot or Renovate update the digest in your `FROM` line.

Everything the image adds is under `/usr/local`. `/usr/local/share/randomcontainers/openssh-client/` holds the version, the source URLs, the build options, the license files and `runtime-deps`, the list of distro packages OpenSSH needs at run time.

## Verifying

Each image has a build provenance attestation from this repository's GitHub Actions run, signed by the shared build workflow in `randomcontainers/ci`:

```sh
gh attestation verify oci://ghcr.io/randomcontainers/openssh-client:latest \
  --repo randomcontainers/openssh-client --signer-repo randomcontainers/ci
```

Each platform image also carries an SPDX SBOM that lists every distro package with its version:

```sh
docker buildx imagetools inspect ghcr.io/randomcontainers/openssh-client:latest --format '{{ json .SBOM }}'
```

Before compiling, the build checks the tarball against the SHA-256 recorded in `package.yml` and its signature against the OpenSSH release signing key in `keys/openssh-release.gpg` (Damien Miller, fingerprint `7168 B983 815A 5EEF 59A4 ADFD 2A3F 414E 7360 60BA`).

## Updates

The project checks the `V_<major>_<minor>_P<n>` tags of [openssh/openssh-portable](https://github.com/openssh/openssh-portable) every 15 minutes. A release is picked up once it is 2 hours old and its tarball and signature are on cdn.openbsd.org; the wait is shorter than the usual 24 hours because most OpenSSH releases fix security issues. The new version and the tarball's SHA-256 are then committed to `package.yml` and the images are rebuilt. A release signed with a key that is not in `keys/openssh-release.gpg` fails to build until the key is added. Only the newest release is built; tags of older versions stay as they were last built.

The images of the current version are also rebuilt when the Ubuntu or Alpine base image changes and at least every 7 days, so distro security fixes, including those for OpenSSL, reach the current tags.

## Building

```sh
docker build -f Dockerfile.ubuntu --target slim \
  --build-arg VERSION=<version> \
  --build-arg SOURCE_SHA256=<sha256 from package.yml> \
  -t openssh-client:local .
```

Use `Dockerfile.alpine` for the Alpine image. `--build-arg JOBS=<n>` limits the number of parallel compile jobs.

## Licenses

OpenSSH's `LICENCE` file lists the terms of its parts, identified together as `SSH-OpenSSH`. The ML-KEM and ML-DSA code compiled into the tools comes from Cryspen's libcrux, which `LICENCE` does not cover, and is used under the MIT license, so the image's license label is `SSH-OpenSSH AND MIT`. `LICENCE` and the libcrux notice (`LICENSE.libcrux`) are in `/usr/local/share/randomcontainers/openssh-client/licenses/`. nss_wrapper, OpenSSL and the other Ubuntu and Alpine packages in the image keep their own licenses.

Every OpenSSH version has a GitHub release in this repository, named `v<version>`, with the exact `openssh-<version>.tar.gz` that was compiled and its signature. The build applies no patches. `/usr/local/share/randomcontainers/openssh-client/source` lists that release and the upstream download URLs.

The files in this repository are available under the MIT license, see [LICENSE](LICENSE). The image contains one of them, `wrapper.sh`, so its `licenses/` directory also has a copy of that license as `LICENSE.wrapper`.

## Requesting a tool

To suggest another tool, use the [Request a tool](https://github.com/randomcontainers/.github/issues/new?template=tool-request.yml) form.
