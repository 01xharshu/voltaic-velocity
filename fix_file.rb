require 'xcodeproj'

project_path = 'VoltaicVelocity.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'VoltaicVelocity' }

group = project.main_group.find_subpath('Sources/VoltaicVelocityApp/Views', false)
file_ref = group.files.find { |f| f.path == 'MarkdownTheme+Volt.swift' || f.name == 'MarkdownTheme+Volt.swift' }

if file_ref
  # Remove the existing one
  target.source_build_phase.remove_file_reference(file_ref)
  file_ref.remove_from_project
end

# Re-add it correctly
file_ref = group.new_file('MarkdownTheme+Volt.swift')
target.source_build_phase.add_file_reference(file_ref)

project.save
puts "Fixed MarkdownTheme+Volt.swift reference."
