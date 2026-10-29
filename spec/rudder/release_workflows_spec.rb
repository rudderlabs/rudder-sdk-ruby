# frozen_string_literal: true

require 'json'
require 'open3'
require 'tmpdir'
require 'yaml'

RSpec.describe 'published Ruby SDK release workflows' do
  def workflow(name)
    YAML.load_file(File.expand_path("../../.github/workflows/#{name}.yml", __dir__))
  end

  def triggers(config)
    config.fetch('on') { config.fetch(true) }
  end

  def require_workflow_tools(*tools)
    tools.each do |tool|
      available = ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |directory|
        File.executable?(File.join(directory, tool))
      end
      skip "#{tool} is required for this workflow script test" unless available
    end
  end

  def notification_payloads(publish_result:, verified:, e2e_result:, uploaded: nil)
    require_workflow_tools('bash', 'jq')
    steps = publish.dig('jobs', 'notify-release', 'steps')
    prepare = steps.find { |step| step['id'] == 'message' }.fetch('run')
    thread = steps.find { |step| step['id'] == 'thread' }.fetch('run')
    Dir.mktmpdir do |dir|
      output = File.join(dir, 'output')
      environment = {
        'GITHUB_OUTPUT' => output,
        'GITHUB_STEP_SUMMARY' => File.join(dir, 'summary'),
        'PUBLISH_RESULT' => publish_result,
        'REGISTRY_VERIFIED' => verified,
        'UPLOADED' => uploaded || (verified == 'true' ? 'true' : ''),
        'E2E_RESULT' => e2e_result,
        'RELEASE_VERSION' => verified == 'true' ? '1.2.3' : '',
        'RELEASE_TAG' => 'v1.2.3',
        'RELEASE_URL' => 'https://github.com/rudderlabs/rudder-sdk-ruby/releases/tag/v1.2.3',
        'RUN_URL' => 'https://github.com/rudderlabs/rudder-sdk-ruby/actions/runs/42',
        'CENTRAL_RUN_URL' => 'https://github.com/rudderlabs/rudder-sdk-e2e-tests/actions/runs/43'
      }
      _stdout, stderr, result = Open3.capture3(environment, 'bash', '-e', '-o', 'pipefail', '-c', prepare)
      raise stderr unless result.success?

      values = File.readlines(output, chomp: true).to_h { |line| line.split('=', 2) }
      root = JSON.parse(values.fetch('root'))
      expect(File.read(environment.fetch('GITHUB_STEP_SUMMARY'))).to include(values.fetch('status'))
      File.write(output, '')
      environment.merge!('ROOT_TS' => '123.456', 'RELEASE_STATUS' => values.fetch('status'),
                         'CHECK_RESULT' => values.fetch('check_result'),
                         'REGISTRY_URL' => values.fetch('registry_url'),
                         'REGISTRY_LABEL' => values.fetch('registry_label'))
      _stdout, stderr, result = Open3.capture3(environment, 'bash', '-e', '-o', 'pipefail', '-c', thread)
      raise stderr unless result.success?

      reply = JSON.parse(File.read(output).split('=', 2).last)
      [root, reply]
    end
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
    expect(steps.find { |step| step['name'] == 'Check out the release event commit' }.fetch('with')).not_to have_key('ref')
    names = steps.map { |step| step['name'] }
    expect(names.index('Verify the release tag still points to the event commit')).to be < names.index('Publish the gem')
    expect(steps.find { |step| step['name'] == 'Verify the release tag still points to the event commit' }.fetch('run')).to include('FETCH_HEAD^{commit}', '$RELEASE_SHA')
    expect(names.index('Verify the published version')).to be > names.index('Publish the gem')
    expect(steps.find { |step| step['name'] == 'Verify the published version' }.fetch('run')).to include('./scripts/publish_gem.sh verify', 'echo "verified=true"')
    expect(job.fetch('outputs')).to include('version' => '${{ steps.release.outputs.version }}',
                                            'origin-sha' => '${{ github.sha }}',
                                            'uploaded' => '${{ steps.upload.outputs.uploaded }}',
                                            'verified' => '${{ steps.verify.outputs.verified }}')
    acceptance = publish.dig('jobs', 'published-e2e')
    expect(acceptance.fetch('needs')).to eq('publish')
    expected_inputs = {
      'package-version' => '${{ needs.publish.outputs.version }}',
      'origin-sha' => '${{ needs.publish.outputs.origin-sha }}'
    }
    expect(acceptance.fetch('with')).to eq(expected_inputs)
  end

  it 'runs the notifier on the first release attempt after both dependencies settle' do
    notify = publish.dig('jobs', 'notify-release')
    expect(notify.fetch('needs')).to eq(%w[publish published-e2e])
    expect(notify.fetch('if')).to include('always()', "github.event.action == 'published'", '!github.event.release.prerelease', "github.run_attempt == '1'")
    expect(notify.fetch('if')).not_to include('needs.publish.outputs.uploaded')
    steps = notify.fetch('steps')
    prepare = steps.find { |step| step['id'] == 'message' }.fetch('run')
    expect(prepare).to include('"$PUBLISH_RESULT" == success && "$REGISTRY_VERIFIED" == true && "$E2E_RESULT" == success')
    expect(prepare).to include('published; validation failed or incomplete', 'publication failed or unconfirmed')
    expect(prepare).to include('S0555JBV36D', 'S03SW7DM8P3', 'S03SHJ20350', 'date -u +%Y-%m-%d')
    thread = steps.find { |step| step['id'] == 'thread' }.fetch('run')
    expect(thread).to include('thread_ts: $ts', 'reply_broadcast: false', 'unfurl_links: false', 'unfurl_media: false')
    expect(thread).to include('$registry_label', 'Release>', 'Validation run>', 'Checks:')
    slack_steps = steps.select { |step| step['uses'].to_s.start_with?('slackapi/slack-github-action@') }
    expect(slack_steps.length).to eq(2)
    expect(slack_steps.map { |step| step['uses'] }.uniq).to eq(['slackapi/slack-github-action@007b2c3c751a190b6f0f040e47ed024deaa72844'])
  end

  {
    'accepted release' => %w[success true success accepted],
    'failed acceptance' => ['success', 'true', 'failure', 'published; validation failed or incomplete'],
    'skipped acceptance' => ['success', 'true', 'skipped', 'published; validation failed or incomplete'],
    'cancelled acceptance' => ['success', 'true', 'cancelled', 'published; validation failed or incomplete'],
    'verified publication with a later job failure' => ['failure', 'true', 'skipped', 'published; validation failed or incomplete'],
    'failed build or upload' => ['failure', '', 'skipped', 'publication failed or unconfirmed; acceptance incomplete'],
    'cancelled publication' => ['cancelled', '', 'skipped', 'publication failed or unconfirmed; acceptance incomplete']
  }.each do |case_name, (publish_result, verified, e2e_result, outcome)|
    it "reports #{case_name} without credentials" do
      root, reply = notification_payloads(publish_result: publish_result, verified: verified, e2e_result: e2e_result)
      expect(root.fetch('text')).to include('Ruby(Async) SDK v1.2.3', outcome)
      expect(root.fetch('text')).not_to include('https://')
      expect(root).to include('unfurl_links' => false, 'unfurl_media' => false)
      expect(reply).to include('thread_ts' => '123.456', 'reply_broadcast' => false,
                               'unfurl_links' => false, 'unfurl_media' => false)
      expect(reply.fetch('text')).to include('Checks:', 'Release>', 'Validation run>', 'https://github.com/rudderlabs/rudder-sdk-e2e-tests/actions/runs/43')
      if verified == 'true'
        expect(reply.fetch('text')).to include('RubyGems v1.2.3', 'exact RubyGems verification: verified')
      else
        expect(reply.fetch('text')).to include('RubyGems package page', 'exact RubyGems verification: unconfirmed')
        expect(reply.fetch('text')).not_to include('package absent', '/versions/1.2.3')
      end
    end
  end

  it 'keeps validation-only retries exact, scoped, and non-cancelling' do
    expect(triggers(validation).keys).to contain_exactly('workflow_call', 'workflow_dispatch')
    expect(validation.fetch('concurrency', {}).fetch('cancel-in-progress', false)).to be(false)
    job = validation.dig('jobs', 'validate')
    expect(job.fetch('uses')).to match(%r{\Arudderlabs/github-action-sdk-e2e/\.github/workflows/published-sdk-e2e\.yml@[0-9a-f]{40}\z})
    expect(job.fetch('uses')).to end_with('@b6de40cc65abe8ee6c6593aac1787aea746b671f')
    expected_inputs = {
      'package-version' => '${{ inputs.package-version || github.ref_name }}',
      'release-app-client-id' => '${{ vars.RELEASE_APP_CLIENT_ID }}'
    }
    expect(job.fetch('with')).to eq(expected_inputs)
    expect(job.fetch('secrets')).to eq('RELEASE_PRIVATE_KEY' => '${{ secrets.RELEASE_PRIVATE_KEY }}')
    expect(job).not_to have_key('steps')
    expect(job.fetch('needs')).to eq('origin')
    origin = validation.dig('jobs', 'origin', 'steps').first
    expect(origin.dig('env', 'ORIGIN_SHA')).to eq('${{ inputs.origin-sha || github.sha }}')
    expect(origin.fetch('run')).to include('"$ORIGIN_SHA" = "$GITHUB_SHA"')
    expect(validation.to_s).not_to match(/gem push|slack-github-action|create.?tag/i)
  end

  it 'reports a confirmed upload separately from missing registry verification' do
    root, _reply = notification_payloads(publish_result: 'failure', verified: '', e2e_result: 'skipped', uploaded: 'true')
    expect(root.fetch('text')).to include('upload completed; registry validation failed or incomplete')
  end

  it 'requires the actual publisher origin and rejects malformed Slack timestamps' do
    require_workflow_tools('bash')
    origin = validation.dig('jobs', 'origin', 'steps').first.fetch('run')
    { 'a' * 40 => true, 'b' * 40 => false }.each do |sha, accepted|
      _stdout, _stderr, status = Open3.capture3({ 'ORIGIN_SHA' => sha, 'GITHUB_SHA' => 'a' * 40 }, 'bash', '-e', '-c', origin)
      expect(status.success?).to eq(accepted)
    end
    guard = publish.dig('jobs', 'notify-release', 'steps').find { |step| step['name'] == 'Require the root message timestamp' }.fetch('run')
    ['', 'invalid', '123.456'].each do |timestamp|
      _stdout, _stderr, status = Open3.capture3({ 'ROOT_TS' => timestamp }, 'bash', '-e', '-c', guard)
      expect(status.success?).to eq(timestamp == '123.456')
    end
  end
end
