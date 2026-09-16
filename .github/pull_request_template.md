## Description

<!-- Briefly describe the changes introduced by this pull request. -->

## Changes

- 
- 

## Type of Change

- [ ] 🚀 New feature (non-breaking change adding functionality)
- [ ] 🐛 Bug fix (non-breaking change fixing an issue)
- [ ] ⚡️ Performance improvement
- [ ] 📝 Documentation update
- [ ] 🧪 Test addition or refactor
- [ ] 🔧 Tooling / CI update

## Verification & Testing

- [ ] Ran `swift test` locally and all tests pass (267+ tests)
- [ ] Added unit tests covering the new functionality
- [ ] Tested on macOS (Sonoma 14.0+ or Sequoia 15.0+)
- [ ] Shared native engine logic between CLI and GUI (no duplicated POSIX logic)
- [ ] Verified PID safety guards (no termination of PID 0, 1, or self)

## Checklist

- [ ] My code adheres to the project's coding standards
- [ ] Updated `README.md` / CLI `--help` text if subcommands or flags were added
- [ ] My changes generate no new compiler warnings
