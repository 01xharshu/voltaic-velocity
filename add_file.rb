require 'xcodeproj'
project_path = 'VoltaicVelocity.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the target
target = project.targets.first

# The file to add
file_path = 'Sources/VoltaicVelocityApp/ViewModels/TerminalManagerViewModel.swift'

# Find the group "Sources/VoltaicVelocityApp/ViewModels"
group = project.main_group.find_subpath(File.dirname(file_path), true)
group.set_source_tree('<group>')

# Add the file reference
file_ref = group.new_reference(File.basename(file_path))

# Add the file to the target's source build phase
target.source_build_phase.add_file_reference(file_ref)

project.save
puts "Successfully added #{file_path} to Xcode project."
