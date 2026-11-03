require 'minitest/autorun'
require 'tmpdir'
require_relative 'unreleased-usns'

class UnreleasedUSNsTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir('unreleased-usns')
    @snapshot = File.join(@directory, 'snapshot.yml')
    @latest = File.join(@directory, 'latest.yml')
    @version = '0.66.0'
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def notice(title, release = 'unreleased')
    { 'title' => title, 'stack_release' => release }
  end

  def write(path, notices)
    File.write(path, notices.to_yaml)
  end

  def test_render_includes_pending_and_same_release_notices_only
    write(@snapshot, [
      notice('USN-1000-1: Python vulnerabilities'),
      notice('USN-1001-1: OpenSSL: multiple vulnerabilities', @version),
      notice('USN-999-1: Already released', '0.65.0'),
      notice('USN-invalid: Not a notice'),
      notice(''),
      notice(nil),
      notice('USN-998-1: Historical entry', Date.new(2026, 1, 1))
    ])
    original = File.read(@snapshot)

    output, = capture_io { UnreleasedUSNs.render(@snapshot, @version) }

    assert_includes output, '## Security fixes'
    assert_includes output, '* [USN-1000-1](https://ubuntu.com/security/notices/USN-1000-1/) Python vulnerabilities'
    assert_includes output, 'OpenSSL: multiple vulnerabilities'
    assert_equal 2, output.scan(/^\* \[USN-/).length
    assert_equal original, File.read(@snapshot)
  end

  def test_render_empty_history_produces_no_section
    [[], [notice('USN-999-1: Already released', '0.65.0')]].each do |notices|
      write(@snapshot, notices)
      output, = capture_io { UnreleasedUSNs.render(@snapshot, @version) }
      assert_empty output
    end
    File.write(@snapshot, '')
    output, = capture_io { UnreleasedUSNs.render(@snapshot, @version) }
    assert_empty output
  end

  def test_mark_only_consumes_notices_in_the_rendered_snapshot
    pending = notice('USN-1000-1: Python vulnerabilities')
    second = notice('USN-1001-1: OpenSSL vulnerabilities')
    added_later = notice('USN-1002-1: Newly detected vulnerability')
    invalid = notice('Not a USN')
    write(@snapshot, [pending, second, invalid])
    write(@latest, [pending, second, added_later, invalid])
    snapshot = File.read(@snapshot)

    capture_io { UnreleasedUSNs.mark(@latest, @snapshot, @version) }

    assert_equal [@version, @version, 'unreleased', 'unreleased'],
                 UnreleasedUSNs.load_notices(@latest).map { |entry| entry['stack_release'] }
    assert_equal snapshot, File.read(@snapshot)
    assert_equal @version, UnreleasedUSNs.load_notices(@latest).first['stack_release']
  end

  def test_mark_preserves_concurrently_released_notices_and_is_idempotent
    first = notice('USN-1000-1: Python vulnerabilities')
    second = notice('USN-1001-1: OpenSSL vulnerabilities')
    write(@snapshot, [first, second])
    write(@latest, [first, second.merge('stack_release' => '0.65.0')])

    capture_io { UnreleasedUSNs.mark(@latest, @snapshot, @version) }
    original = File.read(@latest)
    output, = capture_io { UnreleasedUSNs.mark(@latest, @snapshot, @version) }

    assert_includes output, 'Marked 0 security notices'
    assert_equal original, File.read(@latest)
    assert_equal [@version, '0.65.0'], UnreleasedUSNs.load_notices(@latest).map { |entry| entry['stack_release'] }
  end

  def test_render_after_mark_keeps_notes_for_the_same_release
    write(@snapshot, [notice('USN-1000-1: Python vulnerabilities')])
    write(@latest, UnreleasedUSNs.load_notices(@snapshot))
    before, = capture_io { UnreleasedUSNs.render(@snapshot, @version) }

    capture_io { UnreleasedUSNs.mark(@latest, @snapshot, @version) }
    after, = capture_io { UnreleasedUSNs.render(@latest, @version) }
    next_release, = capture_io { UnreleasedUSNs.render(@latest, '0.67.0') }

    assert_equal before, after
    assert_empty next_release
  end
end
