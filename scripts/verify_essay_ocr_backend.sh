#!/bin/sh

set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export RAILS_ENV=${RAILS_ENV:-test}

cd "$PROJECT_DIR"

bundle exec rails test \
  test/requests/api/v1/essay_ocr_test.rb \
  test/services/essay_ocr/moonshot_service_test.rb \
  test/services/essay_ocr/rate_limiter_test.rb

bundle exec rubocop \
  app/controllers/api/v1/essay_ocr_controller.rb \
  app/services/essay_ocr/moonshot_service.rb \
  app/services/essay_ocr/rate_limiter.rb \
  test/requests/api/v1/essay_ocr_test.rb \
  test/services/essay_ocr/moonshot_service_test.rb \
  test/services/essay_ocr/rate_limiter_test.rb \
  --only Lint

bundle exec rails zeitwerk:check
git diff --check

echo "PASS: Essay OCR backend verification succeeded."
