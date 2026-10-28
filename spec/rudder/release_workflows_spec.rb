# frozen_string_literal: true

require 'spec_helper'
require 'yaml'

RSpec.describe 'published gem release workflows' do
  def workflow(name)
    YAML.load_file(File.expand_path("../../.github/workflows/#{name}.yml", __dir__))
  end

  let(:publish) { workflow('publish') }
  let(:retry_workflow) { workflow('retry-published-gem') }
  let(:validation) { workflow('validate-published-gem') }
  let(:notify) { workflow('slack-notify') }

  # Psych versions differ on whether the YAML 1.1 `on` key is parsed as a boolean.
  def trigger(config)
    config.fetch('on') { config.fetch(true) }
  end

  def steps(config, job)
    config.fetch('jobs').fetch(job).fetch('steps')
  end

  it 'publishes once per non-prerelease, non-cancelling published event' do
    expect(trigger(publish)).to eq('release' => { 'types' => ['published'] })
    expect(publish.dig('concurrency', 'cancel-in-progress')).to eq(false)
    expect(publish.dig('jobs', 'publish', 'if')).to include('!github.event.release.prerelease')
    expect(steps(publish, 'publish').find { |s| s['name'] == 'Check out the release event commit' }.dig('with', 'ref')).to eq('${{ github.sha }}')
    tag_check = steps(publish, 'publish').find { |s| s['name'] == 'Verify the release tag still points to the event commit' }
    expect(tag_check.fetch('run')).to include('refs/tags/$RELEASE_TAG', 'refs/tags/$RELEASE_TAG^{}', '"$tag_commit" == "$RELEASE_SHA"')
    expect(tag_check.dig('env', 'RELEASE_SHA')).to eq('${{ github.sha }}')
  end

  it 'passes the validated version and tag commit only after public verification' do
    publish_job = publish.dig('jobs', 'publish')
    publish_steps = publish_job.fetch('steps')
    expect(publish_steps.map { |s| s['name'] }).to include('Build the gem', 'Publish the gem', 'Verify the published version')
    expect(publish_steps.index { |s| s['name'] == 'Verify the published version' }).to be > publish_steps.index { |s| s['name'] == 'Publish the gem' }
    expect(publish_steps.index { |s| s['name'] == 'Publish the gem' }).to be > publish_steps.index { |s| s['name'] == 'Verify the release tag still points to the event commit' }
    expect(publish_steps.find { |s| s['id'] == 'release' }.fetch('run')).to include('./scripts/publish_gem.sh validate', 'git rev-parse HEAD')
    expect(publish_job.fetch('outputs').values).to include('${{ steps.release.outputs.version }}', '${{ steps.release.outputs.commit }}', '${{ github.event.release.tag_name }}', '${{ steps.push.outputs.pushed }}')
    expect(publish_steps.find { |s| s['id'] == 'push' }.fetch('run')).to include('gem push "$GEM_FILE"', "echo 'pushed=true'")
    accept = publish.dig('jobs', 'acceptance')
    expect(accept.fetch('needs')).to eq('publish')
    expect(accept.fetch('with')).to eq('version' => '${{ needs.publish.outputs.version }}', 'tag' => '${{ needs.publish.outputs.tag }}', 'commit' => '${{ needs.publish.outputs.commit }}')
    expect(accept.fetch('secrets').keys).to eq(['RELEASE_PRIVATE_KEY'])
  end

  it 'gates release-complete on acceptance and reports failed or skipped acceptance honestly' do
    announcement = publish.dig('jobs', 'notify')
    expect(announcement.fetch('needs')).to eq(%w[publish acceptance])
    expect(announcement.fetch('if')).to include('always()', "needs.publish.outputs.pushed == 'true'")
    expect(announcement.dig('with', 'accepted')).to eq("${{ needs.publish.result == 'success' && needs.acceptance.result == 'success' }}")
    expect(announcement.dig('with', 'acceptance_status')).to include("needs.publish.result != 'success'", 'registry verification failed or cancelled', 'needs.acceptance.result')
    expect(trigger(notify).keys).to eq(['workflow_call'])
    expect(notify.dig('jobs', 'notify', 'steps').last.dig('with', 'payload')).to include('published, acceptance {0}', 'release complete:', 'accepted after validation-only retry', 'inputs.validation_url')
  end

  it 'rejects mismatched retry metadata and verifies the source and public version before acceptance' do
    expect(trigger(retry_workflow).keys).to eq(['workflow_dispatch'])
    verify = retry_workflow.dig('jobs', 'verify')
    expect(verify.fetch('if')).to include("github.ref == 'refs/heads/master'")
    check = steps(retry_workflow, 'verify')
    metadata = check.find { |s| s['name'] == 'Check retry inputs and published release metadata' }.fetch('run')
    expect(metadata).to include('[[ "$RELEASE_TAG" == "v$VERSION" ]]', 'releases/tags/$RELEASE_TAG', '.draft, .prerelease')
    expect(metadata).to include('actions/workflows/publish.yml/runs?', 'branch=$RELEASE_TAG', '.head_sha', 'completed', '"$run_sha" == "$RELEASE_COMMIT"', 'Publish the gem', '.conclusion == "success"')
    expect(check.find { |s| s['name'] == 'Check out the recorded release commit' }.dig('with', 'ref')).to eq('${{ inputs.commit }}')
    exact_step = check.find { |s| s['id'] == 'exact' }
    expect(exact_step.fetch('env')).to include('RELEASE_TAG' => '${{ inputs.tag }}', 'VERSION' => '${{ inputs.version }}')
    exact = exact_step.fetch('run')
    expect(exact).to include('git rev-parse HEAD', 'refs/tags/$RELEASE_TAG', './scripts/publish_gem.sh validate', './scripts/publish_gem.sh verify')
    expect(exact.index('./scripts/publish_gem.sh validate')).to be < exact.index('./scripts/publish_gem.sh verify')
    expect(check.map { |s| s['name'] }.join(' ')).not_to match(/Build the gem|Publish the gem|Create tag/)
    expect(retry_workflow.dig('jobs', 'acceptance', 'needs')).to eq('verify')
    expect(retry_workflow.dig('jobs', 'notify', 'if')).to include("needs.acceptance.result == 'success'")
  end

  it 'guards secrets, keeps full E2E explicit, and never cancels live cleanup' do
    job = validation.dig('jobs', 'validate')
    expect(job.fetch('if')).to include("github.event.action == 'published'", "github.ref == 'refs/heads/master'")
    expect(job.dig('concurrency', 'cancel-in-progress')).to eq(false)
    validate_steps = job.fetch('steps')
    blocker = validate_steps.index { |s| s['name'] == 'Block unavailable published-mode contract' }
    token = validate_steps.index { |s| s['id'] == 'token' }
    expect(blocker).to be < token
    expect(validate_steps[token].fetch('with')).to include('owner' => 'rudderlabs', 'repositories' => 'rudder-sdk-e2e-tests', 'permission-actions' => 'write')
    action = validate_steps.last
    expect(action.fetch('uses')).to match(/rudderlabs\/github-action-sdk-e2e@[0-9a-f]{40}/)
    expect(action.fetch('with')).to include('suite' => 'full', 'package-version' => '${{ inputs.version }}', 'source-sha' => '${{ inputs.commit }}', 'source-ref' => '${{ inputs.tag }}')
    expect(trigger(validation).keys).to eq(['workflow_call'])
  end
end
