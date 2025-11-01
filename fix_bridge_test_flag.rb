#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'NoesisNoema.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the LlamaBridgeTest target
target = project.targets.find { |t| t.name == 'LlamaBridgeTest' }

if target
  target.build_configurations.each do |config|
    # Get current flags
    flags = config.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] || ''
    flags_array = flags.is_a?(String) ? flags.split : flags

    # Add BRIDGE_TEST if not present
    unless flags_array.include?('BRIDGE_TEST')
      flags_array << 'BRIDGE_TEST'
      config.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = flags_array.join(' ')
      puts "Added BRIDGE_TEST to #{config.name} configuration"
    else
      puts "BRIDGE_TEST already present in #{config.name} configuration"
    end
  end

  project.save
  puts "✅ Project saved"
else
  puts "❌ LlamaBridgeTest target not found"
  exit 1
end
