#!/usr/bin/env ruby
require 'xcodeproj'

path = 'NoesisNoema.xcodeproj'
project = Xcodeproj::Project.open(path)

puts "✅ Project loaded: #{project.path}"
puts "Targets:"
project.targets.each do |t|
  puts "  - #{t.name}"
end

puts "\n🔍 Checking framework references..."
project.targets.each do |target|
  phase = target.frameworks_build_phase  # ←単数
  next unless phase

  phase.files.each do |file_ref|
    if file_ref.display_name.include?('llama')
      puts "Found llama reference in #{target.name}: #{file_ref.display_name}"
    end
  end
end
