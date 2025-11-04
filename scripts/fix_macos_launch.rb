#!/usr/bin/env ruby
# scripts/fix_macos_launch.rb
#
# Purpose: Fix macOS target to correctly link and embed llama.xcframework
# Usage: ruby scripts/fix_macos_launch.rb
#

require 'xcodeproj'

PROJECT_PATH = 'NoesisNoema.xcodeproj'
MACOS_TARGET_NAME = 'NoesisNoema'

# Framework paths (relative to project root)
FRAMEWORK_SEARCH_PATHS = [
  '$(inherited)',
  '$(PROJECT_DIR)/Frameworks/xcframeworks',
  '$(PROJECT_DIR)/Frameworks/xcframeworks/llama_macos.xcframework/macos-arm64'
]

HEADER_SEARCH_PATHS = [
  '$(inherited)',
  '$(PROJECT_DIR)/Frameworks/xcframeworks/llama_macos.xcframework/macos-arm64/llama.framework/Headers'
]

RUNPATH_SEARCH_PATHS = [
  '$(inherited)',
  '@executable_path/../Frameworks',
  '@loader_path/../Frameworks'
]

def main
  puts "=== macOS Launch Fix Script ==="
  puts "Project: #{PROJECT_PATH}"
  puts "Target: #{MACOS_TARGET_NAME}"
  puts ""

  project = Xcodeproj::Project.open(PROJECT_PATH)
  macos_target = project.targets.find { |t| t.name == MACOS_TARGET_NAME }

  unless macos_target
    puts "❌ Could not find macOS target '#{MACOS_TARGET_NAME}'"
    exit 1
  end

  puts "✅ Found target: #{macos_target.name}"
  puts ""

  # Step 1: Update Build Settings
  puts "Step 1: Updating Build Settings"
  puts "-" * 40

  macos_target.build_configurations.each do |config|
    puts "Configuring: #{config.name}"

    # Framework Search Paths
    config.build_settings['FRAMEWORK_SEARCH_PATHS'] = FRAMEWORK_SEARCH_PATHS
    puts "  ✓ FRAMEWORK_SEARCH_PATHS set"

    # Header Search Paths
    config.build_settings['HEADER_SEARCH_PATHS'] = HEADER_SEARCH_PATHS
    puts "  ✓ HEADER_SEARCH_PATHS set"

    # Runpath Search Paths
    config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = RUNPATH_SEARCH_PATHS
    puts "  ✓ LD_RUNPATH_SEARCH_PATHS set"

    # Remove any ggml library search paths
    if config.build_settings['LIBRARY_SEARCH_PATHS']
      original = config.build_settings['LIBRARY_SEARCH_PATHS']
      cleaned = original.reject { |path| path.to_s.include?('ggml') || path.to_s.include?('build-macos') }
      if cleaned != original
        config.build_settings['LIBRARY_SEARCH_PATHS'] = cleaned
        puts "  ✓ Removed ggml paths from LIBRARY_SEARCH_PATHS"
      end
    end

    # Enable modules
    config.build_settings['CLANG_ENABLE_MODULES'] = 'YES'
    puts "  ✓ CLANG_ENABLE_MODULES = YES"

    # Set valid architectures
    config.build_settings['VALID_ARCHS'] = 'arm64'
    puts "  ✓ VALID_ARCHS = arm64"

    puts ""
  end

  # Step 2: Check framework references
  puts "Step 2: Checking Framework References"
  puts "-" * 40

  # Find llama_macos.xcframework reference
  frameworks_group = project.main_group.children.find { |g| g.path == 'Frameworks' }
  unless frameworks_group
    puts "⚠️  Frameworks group not found in project"
  else
    xcframeworks_group = frameworks_group.children.find { |g| g.path == 'xcframeworks' }
    if xcframeworks_group
      macos_xcframework = xcframeworks_group.children.find { |f| f.path =~ /llama_macos\.xcframework/ }
      if macos_xcframework
        puts "✅ Found llama_macos.xcframework reference"
        puts "   Path: #{macos_xcframework.path}"
      else
        puts "⚠️  llama_macos.xcframework not found in Frameworks/xcframeworks group"
      end
    end
  end

  # Step 3: Remove Copy Files phases that mention ggml
  puts ""
  puts "Step 3: Cleaning Build Phases"
  puts "-" * 40

  copy_phases_removed = 0
  macos_target.copy_files_build_phases.each do |phase|
    files_to_remove = phase.files.select do |file|
      file.display_name.to_s.include?('ggml')
    end

    files_to_remove.each do |file|
      phase.remove_file_reference(file.file_ref) if file.file_ref
      puts "  ✓ Removed #{file.display_name} from Copy Files phase"
      copy_phases_removed += 1
    end
  end

  if copy_phases_removed == 0
    puts "  ✓ No ggml-related files found in Copy Files phases"
  end

  # Step 4: Save project
  puts ""
  puts "Step 4: Saving Project"
  puts "-" * 40

  project.save
  puts "✅ Project saved successfully"

  # Summary
  puts ""
  puts "=" * 40
  puts "Summary of Changes:"
  puts "  • Updated FRAMEWORK_SEARCH_PATHS for macOS target"
  puts "  • Updated HEADER_SEARCH_PATHS for macOS target"
  puts "  • Updated LD_RUNPATH_SEARCH_PATHS for macOS target"
  puts "  • Enabled C/ObjC modules (CLANG_ENABLE_MODULES)"
  puts "  • Set VALID_ARCHS to arm64"
  puts "  • Removed #{copy_phases_removed} ggml-related copy operations" if copy_phases_removed > 0
  puts ""
  puts "Next Steps:"
  puts "  1. Verify framework structure is complete"
  puts "  2. Build: xcodebuild -scheme NoesisNoema build"
  puts "  3. Run the app to verify no launch crash"
  puts "=" * 40
end

if __FILE__ == $0
  main
end
