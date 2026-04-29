# Changelog

All notable changes to the Kasm Helm Chart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- GitHub Actions workflow for automated Helm chart releases via GitHub Pages
- GitHub Actions workflow for OCI registry publishing to ghcr.io
- GitHub Actions workflow for chart linting and validation on PRs
- Dependabot configuration for automated GitHub Actions updates
- CODEOWNERS file for code ownership tracking
- SECURITY.md for security policy and vulnerability reporting
- Chart-testing configuration (ct.yaml)
- Artifact attestations for OCI charts using Sigstore

### Changed
- README.md updated with three installation methods (OCI, HTTP, clone)
- Improved .gitignore to exclude chart artifacts and IDE files

## [1.1181.0] - 2024-XX-XX

### Added
- Initial Helm chart release
- Support for Kasm Workspaces 1.18.1