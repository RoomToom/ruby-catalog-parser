# frozen_string_literal: true

require 'zip'
require 'pathname'
require 'securerandom'
require 'fileutils'

module MyApplicationTokarchuk
  class ArchiveBuilder
    def self.create(root, directory, files)
      FileUtils.mkdir_p(directory)
      path = File.join(directory, "catalog-#{Time.now.utc.strftime('%Y%m%dT%H%M%S')}-#{SecureRandom.hex(4)}.zip")
      Zip::File.open(path, create: true) do |zip|
        files.uniq.sort.each do |file|
          absolute = File.expand_path(file, root)
          relative = Pathname.new(absolute).relative_path_from(Pathname.new(root)).to_s.tr('\\', '/')
          raise ArgumentError, "Archive path outside project: #{relative}" if relative.start_with?('../')
          raise ArgumentError, "Archive input missing: #{relative}" unless File.file?(absolute)

          zip.add(relative, absolute)
        end
      end
      LoggerManager.log_processed_file("Archive created: #{path}")
      path
    end
  end
end
