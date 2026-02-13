#!/usr/bin/env bash
# Ruby/gem utilities
# Note: Ruby version management handled by mise (see .zprofile)

gem_nordoc() {
  gem install --no-document "$1"
}
