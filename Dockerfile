# syntax=docker/dockerfile:1
# check=error=true

# Household's production image. CI builds it once per commit on main
# (.github/workflows/ci.yml) and pushes ghcr.io/<owner>/household:<sha>;
# Kamal runs that tag on this machine, staging then production
# (config/deploy.yml, docs/architecture/delivery.md). Nothing to configure inside: the
# entrypoint makes the secrets Rails needs (bin/docker-secrets) and migrates
# the database (bin/docker-entrypoint).

# The same Ruby as .ruby-version, which development and CI run, on a named
# Debian release: a new release changes the libraries the native gems link
# against (libvips, libpq, Tesseract), so moving to one is a change of its
# own rather than something a rebuild picks up (test/lib/toolchain_versions_test.rb).
ARG RUBY_VERSION=3.4.11
FROM docker.io/library/ruby:$RUBY_VERSION-slim-trixie AS base

WORKDIR /rails

# What the app needs at run time. Tesseract, with its Italian and English
# data, reads the photos of lab reports sent to the assistant
# (LabReports::Ocr). The PostgreSQL client gives the entrypoint pg_isready,
# to wait for the database. jemalloc replaces glibc's allocator, which
# fragments memory under Puma's threads.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips postgresql-client \
      tesseract-ocr tesseract-ocr-ita tesseract-ocr-eng && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# The compilers and headers that native gems need stay in this stage and
# never reach the final image.
FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# The gems first, on their own layer, so a change to the code alone reuses
# it. Bootsnap compiles one file at a time (-j 1): its parallel compiler
# crashes under QEMU, which builds the image for another architecture
# (https://github.com/rails/bootsnap/issues/495).
COPY Gemfile Gemfile.lock ./

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile -j 1 --gemfile

COPY . .

RUN bundle exec bootsnap precompile -j 1 app/ lib/

# Compiling the assets boots the app, which wants a secret key base; the
# real one is made on the container's first boot, so a stand-in does here.
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

# The image that runs: the base, the gems and the code, without the build
# tools.
FROM base

# Run and own only the runtime files as a non-root user for security.
# /rails/secrets is where bin/docker-secrets keeps what it made (a volume
# per destination, config/deploy.*.yml): made here, while still root, since
# /rails itself stays root's.
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    mkdir -p /rails/secrets && chown rails:rails /rails/secrets
USER 1000:1000

COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

# Thruster writes no request log of its own: it would write each path and
# query string as they came, a public file link's token and an invitation's
# included, and Rails already logs every request with those filtered
# (config/initializers/filter_parameter_logging.rb, request_logging.rb).
ENV LOG_REQUESTS="false"

# Kamal only runs an image that names its service (config/deploy.yml).
LABEL service="household"

# The commit this image was built from, for /admin/deployment (CI passes
# it; empty when built by hand). Last, so only this layer changes between builds.
ARG GIT_SHA=""
ENV APP_VERSION=$GIT_SHA

# The entrypoint makes the secrets on a first boot and prepares the
# database. Thruster serves the files and compresses the answers in front of
# Puma; Kamal runs the job worker from the same image with another command.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
