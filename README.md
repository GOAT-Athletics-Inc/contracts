# GOATAI - GOAT Athletics Inc

## Local Setup

- [Install forge](https://book.getfoundry.sh/getting-started/installation) on your machine.
- Run `yarn` to install dependencies

## Run tests

Run tests with Forge: `forge test -vvv` or `forge test -vvv --watch`. See [Forge documentation](https://book.getfoundry.sh/forge/tests) for more options.

### Test coverage

```
forge coverage \
    --report lcov \
    --report summary \--no-match-coverage "(script|test)"
```
