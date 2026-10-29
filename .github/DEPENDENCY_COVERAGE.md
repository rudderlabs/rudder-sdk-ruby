# Resolved dependency inventory

`Gemfile.lock` records the repository's MRI Ruby 2.7 development/test resolution, including indirect gems. The Gemfile uses HTTPS and constrains development `json` to a patched 2.x version because ActiveSupport 6 passes options removed in json 3. The published gemspec requirements and supported Ruby versions are unchanged.

Use the repository's `.ruby-version` and Bundler 2.3.0. Reproduce with `bundle install` and validate with `bundle exec rake`. Refresh deliberately with `bundle update`, review changes, and commit the lock. The generic `ruby` platform allows source-gem installation on Linux; validate the hosted Linux run before acceptance.

The gem has no external runtime dependencies. Development dependencies vary by Ruby version/platform; this lock is not proof of all historical Ruby versions or JRuby coverage. In particular, the gemspec omits `oj` on JRuby. Do not raise the SDK Ruby minimum to accommodate development tools.

After merge, verify concrete and transitive gem versions in GitHub. Existing alerts remain visible. Roll back by reverting the lock and ignore-rule changes; retain HTTPS.
