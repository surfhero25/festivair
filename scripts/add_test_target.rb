#!/usr/bin/env ruby
# Adds a Unit Test Bundle target named "FestivAirTests" to FestivAir.xcodeproj.
# Idempotent: re-running detects the existing target and exits cleanly.
#
# Usage: ruby scripts/add_test_target.rb

require 'xcodeproj'

PROJECT_PATH = 'FestivAir.xcodeproj'
TEST_TARGET_NAME = 'FestivAirTests'
APP_TARGET_NAME = 'FestivAir'
APP_BUNDLE_ID = 'com.festivair.app'
TESTS_DIR = 'FestivAirTests'

project = Xcodeproj::Project.open(PROJECT_PATH)

app_target = project.targets.find { |t| t.name == APP_TARGET_NAME }
abort "[fail] #{APP_TARGET_NAME} target not found" unless app_target

existing_test_target = project.targets.find { |t| t.name == TEST_TARGET_NAME }
if existing_test_target
  # Sync any new source files into the existing test target, then save and exit.
  tests_group = project.main_group.find_subpath(TESTS_DIR, true)
  tests_group.set_source_tree('SOURCE_ROOT')
  tests_group.set_path(TESTS_DIR)
  added = 0
  Dir.glob(File.join(TESTS_DIR, '*.swift')).sort.each do |path|
    basename = File.basename(path)
    file_ref = tests_group.files.find { |f| f.path == basename }
    file_ref ||= tests_group.new_reference(basename)
    unless existing_test_target.source_build_phase.files_references.include?(file_ref)
      existing_test_target.source_build_phase.add_file_reference(file_ref)
      added += 1
    end
  end
  project.save
  puts "[ok] synced #{added} new test source file(s) into #{TEST_TARGET_NAME}"
  exit 0
end

# ── Fix pre-existing pbxproj integrity bugs ──────────────────────────
# Two real defects in the existing project:
#   (1) The Sentry build file is referenced from BOTH the FestivAir
#       Frameworks phase AND the LiveActivity Extension Frameworks phase.
#       A PBXBuildFile can belong to only one phase.
#   (2) The Sentry SPM product is in the FestivAir target's
#       packageProductDependencies but NOT the LiveActivity target's, so
#       the second build-file reference is effectively orphaned.
# Both must be fixed before xcodeproj will round-trip the file.
fwk_phases_to_targets = {}
project.targets.each do |t|
  t.build_phases.each do |bp|
    fwk_phases_to_targets[bp.uuid] = t if bp.isa == 'PBXFrameworksBuildPhase'
  end
end

seen_build_files = {}
fwk_phases_to_targets.each do |phase_uuid, target|
  phase = project.objects_by_uuid[phase_uuid]
  phase.files.dup.each do |bf|
    if seen_build_files.key?(bf.uuid)
      product_ref = bf.product_ref
      # Detach the old shared build file from this phase
      phase.remove_build_file(bf)
      # Create a fresh build file owned by this phase
      new_bf = project.new(Xcodeproj::Project::Object::PBXBuildFile)
      new_bf.product_ref = product_ref if product_ref
      new_bf.file_ref = bf.file_ref if bf.file_ref
      phase.files << new_bf
      # Make sure this target also OWNS the package product dependency
      if product_ref && !target.package_product_dependencies.include?(product_ref)
        target.package_product_dependencies << product_ref
        puts "[fix] added #{product_ref.product_name} as package dep on target '#{target.name}'"
      end
      puts "[fix] split PBXBuildFile for phase '#{phase.display_name}' on target '#{target.name}'"
    else
      seen_build_files[bf.uuid] = phase
    end
  end
end

# ── Create the test target ────────────────────────────────────────────
test_target = project.new_target(
  :unit_test_bundle,
  TEST_TARGET_NAME,
  :ios,
  '17.0',
  project.products_group,
  :swift,
)
test_target.build_configuration_list.build_configurations.each do |config|
  config.build_settings['DEVELOPMENT_TEAM'] = '8JZLCG9CS2'
  config.build_settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = "#{APP_BUNDLE_ID}.tests"
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  # Test host wiring — required for @testable import of the app module
  config.build_settings['TEST_HOST'] =
    '$(BUILT_PRODUCTS_DIR)/FestivAir.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/FestivAir'
  config.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] =
    ['$(inherited)', '@executable_path/Frameworks', '@loader_path/Frameworks']
end

# ── Add a tests/ group + source files ────────────────────────────────
tests_group = project.main_group.find_subpath(TESTS_DIR, true)
tests_group.set_source_tree('SOURCE_ROOT')
tests_group.set_path(TESTS_DIR)

# Add any existing .swift files under FestivAirTests/ to the build phase.
# Test files are written separately (after this script runs); this loop
# wires them up on first creation and on subsequent runs alike.
Dir.glob(File.join(TESTS_DIR, '*.swift')).sort.each do |path|
  basename = File.basename(path)
  file_ref = tests_group.files.find { |f| f.path == basename }
  file_ref ||= tests_group.new_reference(basename)
  unless test_target.source_build_phase.files_references.include?(file_ref)
    test_target.source_build_phase.add_file_reference(file_ref)
  end
end

# ── App target dependency for @testable import ───────────────────────
test_target.add_dependency(app_target)

# ── Create a shared scheme so xcodebuild can find it ─────────────────
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app_target)
scheme.add_test_target(test_target)
scheme.set_launch_target(app_target)
scheme.save_as(PROJECT_PATH, TEST_TARGET_NAME, true)

project.save

puts "[ok] added #{TEST_TARGET_NAME} target with test-host #{APP_TARGET_NAME}"
puts "[ok] scheme saved: #{TEST_TARGET_NAME}"
puts "[ok] tests group: #{TESTS_DIR}/"
puts ""
puts "Add .swift test files to #{TESTS_DIR}/ then re-run this script to wire them in."
