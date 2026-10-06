# mcl-kanban: the crew's kanban boards as an mcl-om service. One board per
# repo; agents claim cards in rank order over the macula mesh; the owner works
# the board from a LiveView on loopback.
#
# PINNED BY DIGEST, and the SAME builder CI tests in, so what ships is what
# was tested: macula-ci-pq ex118 (Elixir 1.18.4 on OTP 28.4.3, Hex and rebar3
# pinned, Rust for macula's NIFs). The runner is macula-pq-runtime from the
# same build date (same Debian, glibc and OpenSSL 3.5). Move the pins together,
# with the image in .github/workflows/ci.yml.
#
# Elixir 1.18, not 1.19: 1.19 cannot assemble a release that carries khepri,
# because horus lists :erts among its applications (elixir-lang/elixir#15934).
ARG BUILDER_IMAGE="ghcr.io/macula-io/macula-ci-pq:ex118-20261005-1119@sha256:f8b10b0cbb04651dd6ddcdd8e9856c12c0927e5bf4e93e8de11f6c0711e300de"
ARG RUNNER_IMAGE="ghcr.io/macula-io/macula-pq-runtime:20261005-1118@sha256:17d2d38c9221cca95620d9820f81e3e334a23527b9cac641f1e1477a8163c998"

# =============================================================================
# BUILD STAGE
# =============================================================================
FROM ${BUILDER_IMAGE} AS builder

WORKDIR /app
ENV MIX_ENV=prod
# macula's QUIC NIF is compiled from source against this OTP.
ENV MACULA_FORCE_SOURCE_BUILD=1

# The TESTED resolve: CI hands this build the mix.lock its test job resolved
# (never committed); scripts/assert_release_matches_lock.sh checks the release
# against it. The glob keeps a local build without a lock working.
COPY mix.exs mix.lock* ./
COPY apps/guide_card_lifecycle/mix.exs ./apps/guide_card_lifecycle/
COPY apps/project_boards/mix.exs ./apps/project_boards/
COPY apps/query_boards/mix.exs ./apps/query_boards/
COPY apps/mcl_kanban/mix.exs ./apps/mcl_kanban/
COPY apps/mcl_kanban_web/mix.exs ./apps/mcl_kanban_web/
COPY config ./config

# Referenced, not just declared: every dependency resolves through a loose
# constraint, so a rebuild on unchanged sources must still run a real deps.get.
ARG CACHE_BUST=unknown
RUN echo "cache_bust=${CACHE_BUST}" > /dev/null

RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

# Cache-busts /assets/app.js and app.css across a redeploy (BuildInfo).
ARG GIT_SHA=dev
ENV GIT_SHA=${GIT_SHA}

COPY apps ./apps
COPY rel ./rel
RUN mix compile

RUN mix esbuild.install --if-missing && \
    mix esbuild mcl_kanban_web && \
    mix esbuild mcl_kanban_web_css

# +S 1: on overlayfs a chmod can race ahead of the parallel ERTS copy.
RUN ELIXIR_ERL_OPTIONS="+S 1" mix release mcl_kanban

# =============================================================================
# RUNTIME STAGE
# =============================================================================
FROM ${RUNNER_IMAGE}

# Links the package to the repository on ghcr.
LABEL org.opencontainers.image.source="https://github.com/macula-services/mcl-kanban"

WORKDIR /app
RUN useradd --create-home --shell /bin/bash app

# Must EXIST in the image, owned by app: a fresh named volume takes its
# ownership from the path it is mounted over.
#   /var/lib/mcl-kanban  the event store and the sqlite read model
#   /etc/mcl/secrets     the node identity key
RUN mkdir -p /var/lib/mcl-kanban /etc/mcl/secrets && \
    chown -R app:app /var/lib/mcl-kanban /etc/mcl/secrets

COPY --from=builder --chown=app:app /app/_build/prod/rel/mcl_kanban ./

USER app

ENV MCL_DATA_DIR=/var/lib/mcl-kanban
ENV MCL_IDENTITY_KEY_PATH=/etc/mcl/secrets/identity.key
ENV MCL_HEALTH_PORT=8492
ENV MCL_HTTP_PORT=4010
# The UI acts as the owner, so it listens on loopback. Run the container on
# the host's network (podman --network=host, docker network_mode: host) and
# the box's own loopback is the only way in. A published port on a bridge is
# NOT the same: every container on that network would reach the UI.
ENV MCL_HTTP_IP=127.0.0.1
VOLUME ["/var/lib/mcl-kanban", "/etc/mcl/secrets"]
EXPOSE 8492 4010

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -fsS "http://127.0.0.1:${MCL_HEALTH_PORT}/health" || exit 1

# Migrations first, then the release (rel/overlays/bin/start): a new version
# brings an older read model up to date before anything reads it.
CMD ["bin/start"]
