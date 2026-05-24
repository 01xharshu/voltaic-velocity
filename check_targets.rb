require 'xcodeproj'
project = Xcodeproj::Project.open('VoltaicVelocity.xcodeproj')
project.targets.each do |target|
  sources = target.source_build_phase.files_references.map(&:path)
  if sources.include?('TerminalManagerViewModel.swift') || sources.include?('Sources/VoltaicVelocityApp/ViewModels/TerminalManagerViewModel.swift')
    puts "File is in target: #{target.name}"
  end
end
