# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.1] - 2026-10-11

### Changed

- Bumped the `ameba` development dependency from `~> 1.6.0` to `~> 1.7.0` and
  fixed the lint violations it introduced (redundant `nil` in control
  expressions, a multiline curly block, and a method exceeding the
  cyclomatic complexity threshold).
- Restructured CI into a `lint` job (format check, ameba, compile check on
  Linux) followed by a `test` job that runs the spec suite on a
  Linux/macOS matrix.

## [0.1.1]

- See git history for changes prior to this changelog.
