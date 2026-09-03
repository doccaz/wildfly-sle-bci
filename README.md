# wildfly-sle-bci

[![Build and publish image](https://github.com/doccaz/wildfly-sle-bci/actions/workflows/build.yml/badge.svg)](https://github.com/doccaz/wildfly-sle-bci/actions/workflows/build.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

WildFly packaged on SUSE's dedicated **SLE BCI OpenJDK** base image, adapted
from [`ericosuse/wildfly-demo`](https://hub.docker.com/r/ericosuse/wildfly-demo).
Multiple WildFly major versions are built and published side by side.

## What this is

The original `ericosuse/wildfly-demo` image was built on the generic
`registry.suse.com/suse/sle15:15.5` base image, with `java-17-openjdk`
installed by hand via `zypper`. This version instead builds on
`registry.suse.com/bci/openjdk` — SUSE's purpose-built BCI image that already
ships a supported OpenJDK runtime — and layers WildFly on top of it.

Everything else about the original image is preserved:

- WildFly, installed at `/opt/wildfly`
- Runs as the unprivileged `wildfly` user (uid/gid `101`), never root
- Two sample WAR deployments: `ROOT.war` and `temperature-converter.war`
  (the classic JBoss/WildFly Celsius↔Fahrenheit JSF+EJB quickstart)
- Ports `8080` (HTTP) and `9990` (management) exposed
- Same startup command (`standalone.sh -b 0.0.0.0 -bmanagement 0.0.0.0`)

## Supported versions

[`versions.json`](versions.json) is the source of truth: it lists every
WildFly version this repo builds, the SLE BCI OpenJDK tag it's paired with,
and which one gets the floating `latest` tag. CI reads this file and builds
one image per entry.

| WildFly | Java (BCI OpenJDK tag) | Image tags |
|---|---|---|
| 32.0.0.Final | 21 | `32.0.0.Final`, `32.0`, `32` |
| 41.0.1.Final | 25 | `41.0.1.Final`, `41.0`, `41`, `latest` |

### Why each version pins the Java tag it does

WildFly 32's `jboss-modules` bootstrap calls the legacy
`java.security.Policy.setPolicy()` API, which JDK 24+ removed outright — it
crashes with `UnsupportedOperationException` on Java 25. Java 21 is the
newest BCI OpenJDK LTS tag WildFly 32 actually boots on. WildFly 41 dropped
that call and boots fine on Java 25, so it's paired with the newer JDK.
**Don't assume a version/JDK pairing works for a version not listed above —
verify it (see "Adding a new WildFly version" below) before changing it.**

## Layout

```
Dockerfile              # parameterized image definition (WILDFLY_VERSION, JAVA_TAG build args)
versions.json           # source of truth: which WildFly/JDK pairs get built
deployments/            # WAR files copied into every image at build time
  ROOT.war
  temperature-converter.war
screenshots/            # for this README
```

## Pulling the pre-built image

Every push to `main` builds and publishes all versions listed in
`versions.json` to GitHub Container Registry via
[`.github/workflows/build.yml`](.github/workflows/build.yml):

```bash
podman pull ghcr.io/doccaz/wildfly-sle-bci:41          # newest, floating minor/major tags
podman pull ghcr.io/doccaz/wildfly-sle-bci:32.0.0.Final # exact pinned version
```

`latest` always points at whichever entry in `versions.json` has
`"latest": true`.

## Building locally

```bash
podman build \
  --build-arg WILDFLY_VERSION=41.0.1.Final \
  --build-arg JAVA_TAG=25 \
  -t wildfly-sle-bci:41.0.1 .
```

Omitting the build args falls back to the `Dockerfile` defaults (currently
WildFly 32.0.0.Final on Java 21). This downloads the WildFly tarball from
GitHub at build time, so it needs network access during `podman build`.

## Running

```bash
podman run -d --name wildfly \
  -p 8080:8080 -p 9990:9990 \
  ghcr.io/doccaz/wildfly-sle-bci:41
```

Give it a few seconds to boot, then check the logs:

```bash
podman logs -f wildfly
```

You should see `WFLYSRV0025: WildFly ... started`.

### Trying the sample app

Both `/` (`ROOT.war`) and `/temperature-converter/` serve the same
Celsius↔Fahrenheit converter (a JSF page backed by a stateless EJB).

Open http://localhost:8080/temperature-converter/ in a browser, enter a
temperature, and click **Convert**:

![Temperature converter app](screenshots/temperature-converter-app.jpg)

### Using the management console

The management console listens on port `9990`. By default there are no
management users configured, so you need to create one before logging in —
same as stock WildFly, this isn't specific to this image:

```bash
podman exec -it wildfly /opt/wildfly/bin/add-user.sh -u admin -p 'ChangeMe123!' -e
```

(`-e` marks it as an admin user with full management access.)

Then open http://localhost:9990 in a browser. WildFly's management interface
uses HTTP authentication, so **the browser will show its own native
login popup** (not an in-page form) — enter the username/password you just
created there:

![Management console homepage](screenshots/mgmt-console-home.jpg)

The **Deployments** tab confirms both sample WARs are deployed and enabled:

![Management console deployments](screenshots/mgmt-console-deployments.jpg)

Management users are stored in
`/opt/wildfly/standalone/configuration/mgmt-users.properties` inside the
container and are **not persisted** across `podman run`s unless you mount
that file (or the whole `standalone/configuration` directory) as a volume.

## Updating

### Adding a new WildFly version

1. Pick a WildFly version and a candidate BCI OpenJDK tag
   (`registry.suse.com/bci/openjdk:<tag>`).
2. Build and smoke-test it locally **before** touching `versions.json`:
   ```bash
   podman build --build-arg WILDFLY_VERSION=<version> --build-arg JAVA_TAG=<tag> \
     -t wildfly-sle-bci:test .
   podman run -d --name wf-test -p 18080:8080 wildfly-sle-bci:test
   curl -i http://127.0.0.1:18080/temperature-converter/
   podman logs wf-test   # confirm WFLYSRV0025 "started" with no exceptions
   podman rm -f wf-test
   ```
   Boot failures on newer JDKs are common — see "Why each version pins the
   Java tag it does" above for the kind of thing to watch for.
3. Add an entry to `versions.json` with the confirmed `wildfly_version` /
   `java_tag` pair, `major`/`minor` tag strings, and `latest: true` on
   whichever entry should own the floating `latest` tag (only one entry
   should have it).
4. Push to `main` — CI builds and publishes every entry in `versions.json`,
   including the new one.

### Replacing the sample deployments

Drop your own `.war`/`.ear`/`.jar` files into `deployments/` (replacing or
adding to the existing ones) and rebuild — the Dockerfile copies everything
in that directory into `/opt/wildfly/standalone/deployments/`. This applies
to every version built from `versions.json`.

### Rebasing on a newer SLE BCI point release

SUSE periodically republishes each `openjdk:<tag>` against newer SLE Service
Packs. Nothing to change here — the next CI run on `main` re-pulls the base
images and rebuilds all versions with `--pull`-equivalent freshness on
GitHub's runners. To force a local rebuild against the latest point release:

```bash
podman pull registry.suse.com/bci/openjdk:21
podman build --pull --build-arg JAVA_TAG=21 --build-arg WILDFLY_VERSION=32.0.0.Final \
  -t wildfly-sle-bci:32.0.0.Final .
```

## Verified

- Both `32.0.0.Final`/Java 21 and `41.0.1.Final`/Java 25 build cleanly and
  boot with no exceptions
- `wildfly` process runs as uid/gid `101`, not root, on every version
- `/` and `/temperature-converter/` both return HTTP 200 and the conversion
  logic works end to end (100 °C → 212 °F, exercising Undertow, JSF/Mojarra,
  Weld/CDI, and the EJB layer) on every version
- Management console reachable on `:9990`, authenticates via HTTP auth, and
  correctly lists both deployments

## CI/CD

[`.github/workflows/build.yml`](.github/workflows/build.yml) reads
`versions.json`, then builds and pushes one image per entry to
`ghcr.io/doccaz/wildfly-sle-bci` on every push to `main` and on manual
dispatch; pull requests build every version but don't push. The workflow
uses the repo's own `GITHUB_TOKEN`, so no extra secrets are needed.

A GitHub Release is also tagged (`vX.Y.Z`, matching the newest WildFly
version added) whenever a new WildFly version lands in `versions.json`, but
the release itself doesn't drive what gets published — `versions.json` on
`main` is the only source of truth for that.

The published package inherits this repository's visibility, so it's
pullable anonymously — no `podman login`/`docker login` needed. If that
ever changes, visibility can be set explicitly from the package's GitHub
settings page
(`github.com/doccaz/wildfly-sle-bci/pkgs/container/wildfly-sle-bci` →
**Package settings** → **Change visibility**).

## License

Licensed under the [GNU General Public License v3.0](LICENSE).
