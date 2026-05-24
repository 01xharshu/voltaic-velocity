require 'xcodeproj'
project = Xcodeproj::Project.open('VoltaicVelocity.xcodeproj')
target = project.targets.first

project.files.each do |f|
    if f.path == "TerminalManagerViewModel.swift"
        target.source_build_phase.remove_file_reference(f)
        f.remove_from_project
    end
end
project.save

group = project.main_group.find_subpath('Sources/VoltaicVelocityApp/ViewModels', false)
if !group
    puts "group not found"
end
file_ref = group.new_file('TerminalManagerViewModel.swift')
target.source_build_phase.add_file_reference(file_ref)
project.save
