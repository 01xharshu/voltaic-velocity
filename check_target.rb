require 'xcodeproj'
project = Xcodeproj::Project.open('VoltaicVelocity.xcodeproj')
target = project.targets.find { |t| t.name == 'VoltaicVelocity' }
sources = target.source_build_phase.files_references.map(&:path)
if sources.include?('TerminalManagerViewModel.swift') || sources.include?('Sources/VoltaicVelocityApp/ViewModels/TerminalManagerViewModel.swift')
  puts "File IS in target."
else
  puts "File IS MISSING from target."
end
