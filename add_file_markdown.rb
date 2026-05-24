require 'xcodeproj'

project_path = 'VoltaicVelocity.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'VoltaicVelocity' }

file_path = 'Sources/VoltaicVelocityApp/Views/MarkdownTheme+Volt.swift'
group = project.main_group.find_subpath('Sources/VoltaicVelocityApp/Views', true)
file_reference = group.new_reference(File.basename(file_path))
target.source_build_phase.add_file_reference(file_reference)

project.save
puts "Added #{file_path} to the project."
