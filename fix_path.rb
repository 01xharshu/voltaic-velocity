require 'xcodeproj'

project_path = 'VoltaicVelocity.xcodeproj'
project = Xcodeproj::Project.open(project_path)

file_ref = project.files.find { |f| f.path == 'MarkdownTheme+Volt.swift' || f.name == 'MarkdownTheme+Volt.swift' }

if file_ref
  file_ref.set_path('Sources/VoltaicVelocityApp/Views/MarkdownTheme+Volt.swift')
  file_ref.source_tree = '<group>'
  project.save
  puts "Fixed path!"
else
  puts "Not found!"
end
