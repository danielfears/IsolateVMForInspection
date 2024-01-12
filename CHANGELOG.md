# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.3] - 2024-01-12

- Added in Warning silence for `New-AzVirtualNetworkSubnetConfig` and `New-AzPublicIpAddress` resources

## [1.0.2] - 2024-01-12

- Removed redundant params block from within script execution function.

## [1.0.1] - 2023-12-21

- Amended params block to support values passed in from GitLab CI

## [1.0.0] - 2023-12-19

- Heavily refactored code to be purely function based, removed multiple versions of script
- Set variables to be script scope to work between functions
- Simplified CI/CD stages to encapsulate variables and login into same container session
- Additional error handling, formatting of outputs and bugfixes
- First production release

## [0.2.0] - 2023-12-11

- Split out version of code with user inputs
- Added new version of `IsolateVM.ps1` that works in a GitLab pipeline
- Added `.gitlab-ci.yml` file to configure GitLab CI/CD
- Added `CHANGELOG.md` file to track updates
- Amended `README.md`` to capture changes to project structure and capture how to configure pipeline version

## [0.1.0] - 2023-12-07

- Initial push of code including `IsolateVM.ps1` and `README.md`
