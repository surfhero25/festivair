fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build + upload to TestFlight (auto-bumps build number to next available)

### ios archive_only

```sh
[bundle exec] fastlane ios archive_only
```

Archive only — no upload (for testing the build pipeline)

### ios tf_build_number

```sh
[bundle exec] fastlane ios tf_build_number
```

Show current TestFlight build number for this app

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
