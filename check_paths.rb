require 'xcodeproj'
project = Xcodeproj::Project.open('VoltaicVelocity.xcodeproj')
target = project.targets.find { |t| t.name == 'VoltaicVelocity' }
target.source_build_phase.files_references.each do |f|
  if f.path.to_s.include?('TerminalManager')
    puts "Found: #{f.path}, Real path: #{f.real_path rescue 'ERROR'}"
  end
end
