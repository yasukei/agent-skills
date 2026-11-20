# Other ecosystems

Handled at a basic level: use the ecosystem's standard commands, the toolchain manager that is already installed, and the commands CI runs. Ask before installing a toolchain manager that is not there.

| Ecosystem | Version pin | Toolchain | Dependencies | Tests |
|---|---|---|---|---|
| Go | `go.mod` `go` (minimum) / `toolchain` (preferred) | Any local Go at or above `go` is valid. With Go 1.21+ and `GOTOOLCHAIN=auto` (default), an older local Go switches to the newer of the two lines and downloads it | `go mod download` | `go test ./...` |
| Rust | `rust-toolchain.toml` / `rust-toolchain` | rustup installs the pinned toolchain on first use inside the repository | `cargo fetch --locked` | `cargo test --locked` |
| Java (Gradle) | `.java-version`, `.sdkmanrc`, Gradle `toolchain` block | sdkman: `sdk env install` (reads `.sdkmanrc`), else mise/asdf | handled by the build | `./gradlew test` (use the wrapper, not a global `gradle`) |
| Java (Maven) | same | same | `./mvnw -B dependency:go-offline` (optional) | `./mvnw -B test` |
| Ruby | `.ruby-version`, `Gemfile` `ruby` | rbenv / mise / asdf / chruby | `bundle install` (with `bundle config set --local deployment true` only when CI does) | `bundle exec rake test` / `bundle exec rspec` |
| PHP | `composer.json` `require.php` | system or mise | `composer install` | `composer test` / `vendor/bin/phpunit` |
| .NET | `global.json` `sdk.version` | `dotnet-install.sh` (ask first) | `dotnet restore`; with `packages.lock.json`, `dotnet restore --locked-mode` | `dotnet test`; after a locked restore, `dotnet test --no-restore` (its implicit restore could rewrite the lockfile) |
| Deno | `deno.json` | mise / installer (ask first) | `deno install` (Deno 2) | `deno test` |

Notes:

- sdkman is a shell function like nvm: source `"$SDKMAN_DIR/bin/sdkman-init.sh"` in each command, and in sbx persist only that line (never its completion script, see `references/environments.md`).
- The wrapper scripts (`gradlew`, `mvnw`) download their build tool on first run; a firewall block shows up there.
- Toolchains a project needs beyond its main language (protoc, a database, a browser) count as environment: install them through an existing manager or the repository's own scripts (`docker compose`, `make deps`), and ask before using the system package manager.
