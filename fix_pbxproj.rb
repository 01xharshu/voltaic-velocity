require 'xcodeproj'
project_path = 'VoltaicVelocity.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

# Remove the incorrect reference
target.source_build_phase.files_references.each do |ref|
    if ref.path == "TerminalManagerViewModel.swift" || ref.path == "Sources/VoltaicVelocityApp/ViewModels/TerminalManagerViewModel.swift"
        target.source_build_phase.remove_file_reference(ref)
        ref.remove_from_project
    end
end

file_path = 'Sources/VoltaicVelocityApp/ViewModels/TerminalManagerViewModel.swift'
group = project.main_group
group_path = "Sources/VoltaicVelocityApp/ViewModels"
group_path.split('/').each do |component|
    group = group.children.find { |c| c.display_name == component || c.path == component } || group.new_group(component)
end

file_ref = group.new_file("TerminalManagerViewModel.swift")
target.source_build_phase.add_file_reference(file_ref)
project.save
