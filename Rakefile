# frozen_string_literal: true

require 'rake/testtask'
Dir.glob(File.join(__dir__, 'lib/tasks/*.rake')).each { |file| load file }

Rake::TestTask.new(:test) do |task|
  # Rake's default loader path is not quoted on Windows when the workspace has spaces.
  task.loader = :direct
  task.warning = false
  task.libs << '.'
  task.libs << 'test'
  task.pattern = 'test/**/*_test.rb'
end

task default: :test
