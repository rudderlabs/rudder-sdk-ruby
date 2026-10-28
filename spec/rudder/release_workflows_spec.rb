# frozen_string_literal: true

require 'spec_helper'
require 'yaml'

RSpec.describe 'published Ruby SDK release workflows' do
  def workflow(name)
    YAML.load_file(File.expand_path("../../.github/workflows/#{name}.yml", __dir__))
  end

  def triggers(config)
    config.fetch('on') { config.fetch(true) }
  end

  let(:publish) { workflow('publish') }
  let(:validation) { workflow('published-sdk-e2e') }

  it 'publishes once from the release event commit and verifies the exact public version before acceptance' do
    expect(triggers(publish)).to eq('release' => { 'types' => ['published'] })
    expect(publish.dig('concurrency', 'cancel-in-progress')).to be(false)
    job = publish.dig('jobs', 'publish')
    expect(job.fetch('if')).to include('!github.event.release.prerelease')
    expect(job.fetch('runs-on')).to eq('ubuntu-24.04')
    steps = job.fetch('steps')
    expect(steps.find { |step| step['name'] == 'Check out the release event commit' }.dig('with', 'ref')).to eq('${{ github.sha }}')
    names = steps.map { |step| step['name'] }
    expect(names.index('Verify the release tag still points to the event commit')).to be < names.index('Publish the gem')
    expect(steps.find { |step| step['name'] == 'Verify the release tag still points to the event commit' }.fetch('run')).to include('FETCH_HEAD^{commit}', '$RELEASE_SHA')
    expect(names.index('Verify the published version')).to be > names.index('Publish the gem')
    expect(steps.find { |step| step['name'] == 'Verify the published version' }.fetch('run')).to include('./scripts/publish_gem.sh verify')
    expect(job.fetch('outputs')).to include('version' => '${{ steps.release.outputs.version }}',
                                            'origin-sha' => '${{ github.sha }}',
                                            'uploaded' => '${{ steps.upload.outputs.uploaded }}')
    acceptance = publish.dig('jobs', 'published-e2e')
    expect(acceptance.fetch('needs')).to eq('publish')
    expected_inputs = {
      'package-version' => '${{ needs.publish.outputs.version }}',
      'origin-sha' => '${{ needs.publish.outputs.origin-sha }}'
    }
    expect(acceptance.fetch('with')).to eq(expected_inputs)
  end

  it 'announces success only after acceptance and reports every post-upload failure as incomplete' do
    notify = publish.dig('jobs', 'notify-release')
    expect(notify.fetch('needs')).to eq(%w[publish published-e2e])
    expect(notify.fetch('if')).to include('always()', "needs.publish.outputs.uploaded == 'true'")
    steps = notify.fetch('steps')
    prepare = steps.find { |step| step['id'] == 'message' }.fetch('run')
    expect(prepare).to include('"$PUBLISH_RESULT" == success && "$E2E_RESULT" == success')
    expect(prepare).to include('published; validation failed or incomplete', 'unfurl_links: false', 'unfurl_media: false')
    expect(prepare).to include('S0555JBV36D', 'S03SW7DM8P3', 'S03SHJ20350', 'date -u +%Y-%m-%d')
    thread = steps.find { |step| step['id'] == 'thread' }.fetch('run')
    expect(thread).to include('thread_ts: $ts', 'reply_broadcast: false', 'unfurl_links: false', 'unfurl_media: false')
    expect(thread).to include('RubyGems v', 'Release>', 'Validation run>', 'Checks:')
    slack_steps = steps.select { |step| step['uses'].to_s.start_with?('slackapi/slack-github-action@') }
    expect(slack_steps.length).to eq(2)
    expect(slack_steps.map { |step| step['uses'] }.uniq).to eq(['slackapi/slack-github-action@007b2c3c751a190b6f0f040e47ed024deaa72844'])
  end

  it 'keeps validation-only retries exact, scoped, and non-cancelling' do
    expect(triggers(validation).keys).to contain_exactly('workflow_call', 'workflow_dispatch')
    expect(validation.dig('concurrency', 'cancel-in-progress')).to be(false)
    job = validation.dig('jobs', 'validate')
    expect(job.fetch('runs-on')).to eq('ubuntu-latest')
    steps = job.fetch('steps')
    guard = steps.find { |step| step['name'] == 'Require an exact release tag' }.fetch('run')
    expect(guard).to include('"$GITHUB_REF_TYPE" != tag', '"$ORIGIN_SHA" != "$GITHUB_SHA"')
    expect(guard).to include('"${PACKAGE_VERSION#v}" != "${RELEASE_TAG#v}"')
    expect(steps.find { |step| step['name'] == 'Verify the tag still resolves to the event commit' }.fetch('run')).to include('git rev-parse HEAD', '$ORIGIN_SHA')
    token = steps.find { |step| step['id'] == 'token' }
    expect(steps.index(token)).to be > steps.index { |step| step['name'] == 'Verify the tag still resolves to the event commit' }
    expect(token.fetch('with')).to include('owner' => 'rudderlabs', 'repositories' => 'rudder-sdk-e2e-tests', 'permission-actions' => 'write')
    action = steps.last
    expect(action.fetch('with')).to include('package-version' => '${{ inputs.package-version || github.ref_name }}', 'suite' => 'full')
    expect(steps.find { |step| step['name'] == 'Require an exact release tag' }.dig('env', 'ORIGIN_SHA')).to eq('${{ inputs.origin-sha || github.sha }}')
    expect(steps.to_s).not_to match(/gem push|slack-github-action|create.?tag/i)
  end
end
