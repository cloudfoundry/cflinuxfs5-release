#!/usr/bin/env ruby

require 'date'
require 'yaml'

module UnreleasedUSNs
  def self.load_notices(path)
    YAML.safe_load(File.read(path), permitted_classes: [Date, Time]) || []
  end

  def self.release_notices(notices, version)
    notices.select do |notice|
      id = notice['title'].to_s.split(':', 2).first.to_s.strip
      id.match?(/\AUSN-\d+-\d+\z/) &&
        ['unreleased', version].include?(notice['stack_release'].to_s)
    end
  end

  def self.render(path, version)
    notices = release_notices(load_notices(path), version)
    return if notices.empty?

    puts "## Security fixes\n\nNotably, this release addresses:\n\n"
    notices.each do |notice|
      id, description = notice.fetch('title').split(':', 2).map(&:strip)
      puts "* [#{id}](https://ubuntu.com/security/notices/#{id}/) #{description}".rstrip
    end
    puts
  end

  def self.mark(path, snapshot_path, version)
    titles = release_notices(load_notices(snapshot_path), version).map { |notice| notice.fetch('title') }
    notices = load_notices(path)
    count = 0
    notices.each do |notice|
      next unless notice['stack_release'] == 'unreleased' && titles.include?(notice['title'])

      notice['stack_release'] = version
      count += 1
    end
    File.write(path, notices.to_yaml) if count.positive?
    puts "Marked #{count} security notices as released in #{version}"
  end
end

if $PROGRAM_NAME == __FILE__
  mode, *args = ARGV
  case mode
  when 'render'
    abort 'Usage: unreleased-usns.rb render <snapshot.yml> <version>' unless args.length == 2
    UnreleasedUSNs.render(*args)
  when 'mark'
    abort 'Usage: unreleased-usns.rb mark <latest.yml> <snapshot.yml> <version>' unless args.length == 3
    UnreleasedUSNs.mark(*args)
  else
    abort 'Usage: unreleased-usns.rb <render|mark> ...'
  end
end
