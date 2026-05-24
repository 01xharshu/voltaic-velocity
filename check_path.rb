require 'xcodeproj'
project = Xcodeproj::Project.open('VoltaicVelocity.xcodeproj')
target = project.targets.find { |t| t.name == 'VoltaicVelocity' }
file = target.source_build_phase.files_references.find { |f| f.path == 'TerminalManagerViewModel.swift' || f.name == 'TerminalManagerViewModel.swift' }
if file
  puts "File Ref Path: #{file.path}"
  puts "File Ref Real Path: #{file.real_path}"
else
  puts "File Ref NOT FOUND"
end
