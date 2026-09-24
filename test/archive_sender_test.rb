# frozen_string_literal: true

require_relative 'test_helper'
Sidekiq.testing!(:fake)

class ArchiveSenderTest < LabTest
  def test_job_enqueues_and_pony_builds_email_with_correct_attachment
    @config['mail'].merge!('from' => 'lab@example.test', 'to' => 'student@example.test')
    directory = File.join(@temporary, 'output/archives')
    FileUtils.mkdir_p(directory)
    archive = File.join(directory, 'test.zip')
    File.binwrite(archive, 'test archive bytes')
    received = nil
    Sidekiq::Testing.fake! do
      ArchiveSender.clear
      ArchiveSender.perform_async('output/archives/test.zip', 'student@example.test')
      assert_equal 1, ArchiveSender.jobs.size
      AppConfigLoader.stub(:config, @config) do
        Pony.stub(:mail, ->(options) { received = options }) { ArchiveSender.drain }
      end
    end
    assert_equal 'student@example.test', received[:to]
    assert_equal :smtp, received[:via]
    assert_equal 'test archive bytes', received[:attachments]['test.zip']
    assert_empty ArchiveSender.jobs
  end

  def test_sender_rejects_files_outside_archive_directory
    FileUtils.mkdir_p(File.join(@temporary, 'output/archives'))
    File.write(File.join(@temporary, 'secret.zip'), 'private')
    AppConfigLoader.stub(:config, @config) do
      assert_raises(ArgumentError) { ArchiveSender.new.perform('secret.zip', 'student@example.test') }
    end
  end
end
